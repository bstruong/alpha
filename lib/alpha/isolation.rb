# frozen_string_literal: true

require "open3"
require "rbconfig"
require "shellwords"
require "tmpdir"

module Alpha
  # Fail-closed Linux namespace isolation for evaluated agents (bubblewrap).
  #
  # The agent sees only:
  # - the task app (writable)
  # - explicitly listed runtime libraries / harness paths (read-only)
  # - an empty temporary HOME
  # - a minimal fixed PATH
  # - an explicit environment allowlist
  # - network only when required for the inference provider
  #
  # Sibling seed trees, solution/grader paths, host HOME, SSH keys, and cloud
  # credential directories are not mounted into the namespace.
  class Isolation
    class UnavailableError < StandardError; end

    DEFAULT_BWRAP = "bwrap"
    AGENT_HOME = "/home/agent"
    MINIMAL_PATH = "/usr/local/bin:/usr/bin:/bin"

    # Host paths that may contain secrets — never bind into the agent namespace.
    FORBIDDEN_BIND_PREFIXES = [
      "#{Dir.home}/.ssh",
      "#{Dir.home}/.aws",
      "#{Dir.home}/.config/gcloud",
      "#{Dir.home}/.azure",
      "#{Dir.home}/.kube",
      "#{Dir.home}/.gnupg",
      "/root",
      "/etc/ssh"
    ].freeze

    ENV_ALLOWLIST = %w[
      PATH
      HOME
      LANG
      LC_ALL
      LC_CTYPE
      TERM
      TMPDIR
      TMP
      TEMP
      USER
      LOGNAME
      RAILS_ENV
      BUNDLE_GEMFILE
      BUNDLE_APP_CONFIG
      BUNDLE_PATH
      RUBYOPT
      GEM_HOME
      GEM_PATH
      ALPHA_WEB_RAILS_BUNDLE
      PI_CODING_AGENT_DIR
      PI_BIN
      LLAMA_SERVER_URL
      LLAMA_BASE_URL
      OPENAI_BASE_URL
      OPENAI_API_BASE
      OPENAI_API_KEY
      NODE_PATH
      npm_config_cache
      SSL_CERT_FILE
      SSL_CERT_DIR
      CURL_CA_BUNDLE
      REQUESTS_CA_BUNDLE
      ALPHA_CHROME_PATH
      BROWSER_PATH
      CHROME_PATH
      CHROMIUM_FLAGS
    ].freeze

    RO_ROOT_CANDIDATES = %w[
      /usr
      /lib
      /lib64
      /lib32
      /bin
      /sbin
      /etc/ssl
      /etc/ca-certificates
      /etc/pki
      /etc/resolv.conf
      /etc/hosts
      /etc/nsswitch.conf
      /etc/localtime
      /etc/timezone
      /etc/passwd
      /etc/group
      /etc/protocols
      /etc/services
    ].freeze

    class << self
      def bwrap_bin
        ENV.fetch("ALPHA_BWRAP", DEFAULT_BWRAP)
      end

      def available?
        return @available unless @available.nil?

        @available = probe_available?
      end

      def reset_availability!
        remove_instance_variable(:@available) if instance_variable_defined?(:@available)
        remove_instance_variable(:@proc_mount_supported) if instance_variable_defined?(:@proc_mount_supported)
      end

      # Test/diagnostic override: force Isolation.available? without stubbing.
      def force_unavailable!
        @available = false
      end

      def require_available!
        return true if available?

        raise UnavailableError,
              "Linux namespace sandbox unavailable (#{bwrap_bin}). " \
              "Evaluated agents must not run unsandboxed; install bubblewrap " \
              "or set ALPHA_BWRAP to a working binary."
      end

      # Build argv + cleared env for Process.spawn. Never falls back to bare cmd.
      def wrap(command, env:, chdir:, writable_paths:, read_only_paths: [],
               network: true, extra_env: {})
        require_available!
        command = Array(command)
        raise ArgumentError, "command required" if command.empty?

        writable = normalize_paths(writable_paths)
        read_only = normalize_paths(read_only_paths)
        assert_safe_binds!(writable + read_only)

        chdir = File.expand_path(chdir)
        unless writable.any? { |path| chdir == path || chdir.start_with?("#{path}/") }
          raise ArgumentError, "chdir #{chdir} must be under a writable bind"
        end

        filtered = filter_env(env).merge(filter_env(extra_env))
        filtered["HOME"] = AGENT_HOME
        filtered["PATH"] = agent_path(filtered["PATH"])
        filtered["TMPDIR"] ||= "/tmp"
        filtered["TMP"] ||= "/tmp"
        filtered["TEMP"] ||= "/tmp"
        filtered["LANG"] ||= "C.UTF-8"
        filtered["USER"] ||= "agent"
        filtered["LOGNAME"] ||= "agent"

        argv = [ resolved_bwrap ]
        argv.concat(%w[--unshare-all --die-with-parent --new-session])
        argv << "--share-net" if network
        # Prefer --proc when the runtime allows a fresh procfs (bare metal /
        # privileged). Nested Docker/Kubernetes often denies that mount; binding
        # the caller's /proc keeps filesystem isolation while remaining fail-closed
        # on missing bubblewrap itself.
        if proc_mount_supported?
          argv.concat(%w[--proc /proc --dev /dev])
        else
          argv.concat(%w[--ro-bind /proc /proc --dev /dev])
        end
        argv.concat(%w[--tmpfs /tmp --tmpfs /home --dir /home/agent --chmod 0700 /home/agent])

        RO_ROOT_CANDIDATES.each { |path| append_ro_bind!(argv, path) }
        runtime_roots.each { |path| append_ro_bind!(argv, path) }
        read_only.each { |path| append_ro_bind!(argv, path) }
        writable.each { |path| append_bind!(argv, path) }

        argv.concat(["--chdir", chdir, "--clearenv"])
        filtered.each do |key, value|
          argv.concat(["--setenv", key.to_s, value.to_s])
        end
        argv << "--"
        argv.concat(command.map(&:to_s))

        # Env is embedded via --setenv/--clearenv; spawn with a minimal husk.
        [ argv, { "PATH" => MINIMAL_PATH } ]
      end

      def run(*command, env: {}, chdir:, writable_paths:, read_only_paths: [],
              network: true, extra_env: {})
        argv, spawn_env = wrap(
          command,
          env: env,
          chdir: chdir,
          writable_paths: writable_paths,
          read_only_paths: read_only_paths,
          network: network,
          extra_env: extra_env
        )
        Open3.capture2e(spawn_env, *argv)
      end

      def filter_env(env)
        out = {}
        (env || {}).each do |key, value|
          name = key.to_s
          next unless ENV_ALLOWLIST.include?(name)
          next if value.nil?

          out[name] = value.to_s
        end
        out
      end

      # Install root for an npm-layout Pi binary (…/node_modules/.bin/pi → …/).
      # Binding only dirname(PI_BIN) leaves the shim target unmounted inside bwrap.
      def pi_package_root(pi_bin = nil)
        bin = pi_bin.nil? || pi_bin.to_s.empty? ? Alpha.config.pi_bin : pi_bin
        return nil if bin.nil? || bin.to_s.empty?

        path = File.expand_path(bin.to_s)
        if (m = path.match(%r{\A(.+)/node_modules/\.bin/[^/]+\z}))
          return m[1] if File.directory?(m[1])
        end

        start = File.exist?(path) ? File.realpath(path) : path
        dir = File.directory?(start) ? start : File.dirname(start)
        candidates = []
        while dir && dir != "/" && dir != "."
          candidates << dir if File.directory?(File.join(dir, "node_modules"))
          parent = File.dirname(dir)
          break if parent == dir

          dir = parent
        end
        return candidates.last if candidates.any?

        File.dirname(path)
      rescue StandardError
        bin && !bin.to_s.empty? ? File.dirname(File.expand_path(bin.to_s)) : nil
      end

      # True when PI_BIN is visible under the same Isolation binds trials use.
      # Host File.executable? is not sufficient — npm shims need the package tree.
      def pi_visible_in_sandbox?(pi_bin = nil)
        bin = pi_bin.nil? || pi_bin.to_s.empty? ? Alpha.config.pi_bin : pi_bin
        return false if bin.nil? || bin.to_s.empty?
        return false unless File.exist?(bin)
        return false unless available?

        root = pi_package_root(bin)
        Dir.mktmpdir("alpha-pi-visibility-") do |dir|
          probe = <<~RUBY
            path = ENV.fetch("PI_BIN")
            abort("missing") unless File.exist?(path)
            puts "ok"
          RUBY
          File.write(File.join(dir, "probe.rb"), probe)
          out, status = run(
            RbConfig.ruby, "probe.rb",
            env: { "PI_BIN" => File.expand_path(bin), "LANG" => "C.UTF-8" },
            chdir: dir,
            writable_paths: [ dir ],
            read_only_paths: [ root ].compact,
            network: false
          )
          status.success? && out.to_s.include?("ok")
        end
      rescue UnavailableError, StandardError
        false
      end

      private

        def probe_available?
          bin = resolved_bwrap
          return false unless bin && File.executable?(bin)

          Dir.mktmpdir("alpha-isolation-probe-") do |dir|
            out, status = Open3.capture2e(
              { "PATH" => MINIMAL_PATH },
              bin,
              "--unshare-all", "--die-with-parent",
              "--ro-bind", "/proc", "/proc",
              "--dev", "/dev",
              "--ro-bind", "/usr", "/usr",
              "--ro-bind", "/bin", "/bin",
              "--ro-bind-try", "/lib", "/lib",
              "--ro-bind-try", "/lib64", "/lib64",
              "--tmpfs", "/tmp",
              "--bind", dir, dir,
              "--chdir", dir,
              "--", "true"
            )
            return true if status.success?

            warn "[alpha] isolation probe failed: #{out.strip}" if ENV["ALPHA_DEBUG"]
            false
          end
        rescue StandardError => e
          warn "[alpha] isolation probe error: #{e.class}: #{e.message}" if ENV["ALPHA_DEBUG"]
          false
        end

        def proc_mount_supported?
          return @proc_mount_supported unless @proc_mount_supported.nil?

          bin = resolved_bwrap
          unless bin && File.executable?(bin)
            @proc_mount_supported = false
            return @proc_mount_supported
          end

          Dir.mktmpdir("alpha-isolation-proc-") do |dir|
            _out, status = Open3.capture2e(
              { "PATH" => MINIMAL_PATH },
              bin,
              "--unshare-all", "--die-with-parent",
              "--proc", "/proc",
              "--dev", "/dev",
              "--ro-bind", "/usr", "/usr",
              "--ro-bind", "/bin", "/bin",
              "--ro-bind-try", "/lib", "/lib",
              "--ro-bind-try", "/lib64", "/lib64",
              "--tmpfs", "/tmp",
              "--bind", dir, dir,
              "--chdir", dir,
              "--", "true"
            )
            @proc_mount_supported = status.success?
          end
        rescue StandardError
          @proc_mount_supported = false
        end

        def resolved_bwrap
          bin = bwrap_bin
          return bin if bin.start_with?("/") && File.executable?(bin)

          found = `command -v #{Shellwords.escape(bin)} 2>/dev/null`.strip
          found.empty? ? nil : found
        rescue StandardError
          nil
        end

        def normalize_paths(paths)
          Array(paths).compact.map { |p| File.expand_path(p) }.uniq
        end

        def assert_safe_binds!(paths)
          paths.each do |path|
            FORBIDDEN_BIND_PREFIXES.each do |prefix|
              next unless path == prefix || path.start_with?("#{prefix}/")

              raise ArgumentError, "refusing to bind sensitive path into agent namespace: #{path}"
            end
          end
        end

        def append_ro_bind!(argv, path)
          return unless path && File.exist?(path)

          argv.concat(["--ro-bind", path, path])
        end

        def append_bind!(argv, path)
          raise ArgumentError, "writable path missing: #{path}" unless File.exist?(path)

          argv.concat(["--bind", path, path])
        end

        def runtime_roots
          roots = []
          ruby_prefix = RbConfig::CONFIG["prefix"]
          roots << ruby_prefix if ruby_prefix && !ruby_prefix.empty?
          roots << File.dirname(RbConfig.ruby)

          node = first_executable(%w[node])
          if node
            roots << File.dirname(node)
            # Cover mise/nvm-style prefixes (…/bin/node → prefix).
            roots << File.expand_path("../..", node)
          end

          pi = Alpha.config.pi_bin
          if pi && !pi.to_s.empty? && File.exist?(pi)
            root = pi_package_root(pi)
            roots << root if root
          end

          roots.map { |p| File.expand_path(p) }.uniq.select { |p| File.exist?(p) }
        end

        def first_executable(names)
          names.each do |name|
            found = `command -v #{Shellwords.escape(name)} 2>/dev/null`.strip
            return found unless found.empty?
          end
          nil
        rescue StandardError
          nil
        end

        def agent_path(_requested)
          parts = []
          parts << File.dirname(RbConfig.ruby)
          node = first_executable(%w[node])
          parts << File.dirname(node) if node
          parts.concat(MINIMAL_PATH.split(":"))
          parts.uniq.join(File::PATH_SEPARATOR)
        end
    end
  end
end
