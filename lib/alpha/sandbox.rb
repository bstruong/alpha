# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

module Alpha
  # Isolated directory-copy sandbox for one task trial.
  # Deliberately avoids git worktrees so the agent cannot inspect parent repo history
  # or read tasks/*/solution.patch and verification_test.rb.
  class Sandbox
    SKIP_DIRS = %w[tmp log storage].freeze

    attr_reader :path, :work_dir, :seeded_path, :library_dir

    def self.provision(task, library_dir: nil, work_dir: nil)
      resolved_library = library_dir || File.expand_path("../../library", task.dir)
      raise ArgumentError, "Base library directory not found: #{resolved_library}" unless File.directory?(resolved_library)

      resolved_work = work_dir || Dir.mktmpdir("alpha-#{task.name}-")
      app_dir = File.join(resolved_work, "app")
      seeded_dir = File.join(resolved_work, "seeded")

      copy_tree(resolved_library, app_dir)

      sandbox = new(
        path: app_dir,
        work_dir: resolved_work,
        seeded_path: seeded_dir,
        library_dir: resolved_library
      )

      # Apply environment.patch before db:prepare so tasks that strip migrations /
      # schema land on a DB that matches the broken seed (vertical-slice L4+).
      unless sandbox.apply_patch!(task.environment_patch)
        raise "environment.patch failed to apply for #{task.name}"
      end

      if sandbox.requires_db?(task)
        prepared, prepare_out = sandbox.prepare_db!
        raise "db:prepare failed for #{task.name}:\n#{prepare_out}" unless prepared
      end

      sandbox.snapshot_seeded!
      sandbox
    end

    def self.copy_tree(source, dest)
      FileUtils.rm_rf(dest)
      FileUtils.mkdir_p(dest)
      Dir.each_child(source) do |name|
        next if SKIP_DIRS.include?(name)

        FileUtils.cp_r(File.join(source, name), dest, preserve: true)
      end
      SKIP_DIRS.each { |name| FileUtils.mkdir_p(File.join(dest, name)) }
    end

    def initialize(path:, work_dir: nil, seeded_path: nil, library_dir: nil)
      @path = path
      @work_dir = work_dir || File.dirname(path)
      @seeded_path = seeded_path || File.join(@work_dir, "seeded")
      @library_dir = library_dir || path
    end

    def child_env
      bindir = File.dirname(RbConfig.ruby)
      env = {
        "PATH" => "#{bindir}#{File::PATH_SEPARATOR}#{ENV.fetch("PATH", "")}",
        "RAILS_ENV" => "test",
        "BUNDLE_GEMFILE" => File.join(path, "Gemfile"),
        "BUNDLE_APP_CONFIG" => File.join(path, ".bundle"),
        "RUBYOPT" => "",
        "HOME" => ENV.fetch("HOME", "")
      }
      # Propagate Chrome binary for Ferrum/Cuprite product graders.
      %w[ALPHA_CHROME_PATH BROWSER_PATH CHROME_PATH].each do |key|
        env[key] = ENV[key] if ENV[key] && !ENV[key].empty?
      end
      env
    end

    def run_in_clean_env(&block)
      if defined?(Bundler) && Bundler.respond_to?(:with_unbundled_env)
        Bundler.with_unbundled_env(&block)
      else
        yield
      end
    end

    # Chat JSON / pattern graders never boot the Rails library; skip db:prepare
    # so Watchtower/CPU runners don't need scenario gem caches for ops roles.
    def requires_db?(task)
      return false unless File.file?(File.join(path, "bin", "rails"))

      executor = task.respond_to?(:executor_type) ? task.executor_type.to_s : ""
      grader = task.respond_to?(:grader_type) ? task.grader_type.to_s : ""
      return false if %w[openai_chat_completions openai stateless].include?(executor) &&
                      %w[json_schema pattern_deny].include?(grader)

      true
    end

    def prepare_db!
      rails_bin = File.join(path, "bin", "rails")
      return [ true, "No bin/rails; skipped db:prepare" ] unless File.file?(rails_bin)

      run_in_clean_env do
        out, status = Open3.capture2e(child_env, "bin/rails", "db:prepare", chdir: path)
        [ status.success?, out ]
      end
    end

    def apply_patch!(patch_path)
      return true unless patch_path

      _out, status = Open3.capture2(
        "patch", "-p1", "--forward", "--batch", "-d", path, "-i", patch_path
      )
      status.success?
    end

    def snapshot_seeded!
      self.class.copy_tree(path, seeded_path)
    end

    def restore_protected!(task)
      return unless File.directory?(seeded_path)

      task.restore_except.each do |rel|
        src = File.join(path, rel)
        next unless File.file?(src)

        kept = File.join(path, "tmp", "kept", rel)
        FileUtils.mkdir_p(File.dirname(kept))
        FileUtils.cp(src, kept)
      end

      task.restore.each do |rel|
        src = File.join(seeded_path, rel)
        dest = File.join(path, rel)
        next unless File.exist?(src)

        FileUtils.rm_rf(dest)
        FileUtils.cp_r(src, dest, preserve: true)
      end

      task.restore_except.each do |rel|
        edited = File.join(path, "tmp", "kept", rel)
        next unless File.file?(edited)

        dest = File.join(path, rel)
        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp(edited, dest)
      end
    end

    def diff_from_seeded(dest_file = nil)
      return "" unless File.directory?(seeded_path)

      out, status = Open3.capture2("diff", "-ru", seeded_path, path)
      raise "diff failed" unless status.success? || status.exitstatus == 1

      body = out.lines.reject { |line| line.include?("/tmp/") && line.start_with?("diff ") }.join
      body = body.gsub("#{seeded_path}/", "a/").gsub("#{path}/", "b/")
      File.write(dest_file, body) if dest_file
      body
    end

    def drifted_files(except = [])
      return [] unless File.directory?(seeded_path)

      failures = []
      Dir.glob(File.join(seeded_path, "**/*"), File::FNM_DOTMATCH).each do |src|
        next unless File.file?(src)

        rel = src.delete_prefix("#{seeded_path}/")
        next if rel.start_with?(".") && !rel.include?("/")
        next if except.any? { |allowed| rel == allowed }

        dest = File.join(path, rel)
        next if File.file?(dest) && FileUtils.compare_file(src, dest)

        failures << rel
      end
      failures
    end

    def modified_ruby_files
      return [] unless File.directory?(path)

      files = []
      Dir.glob(File.join(path, "**/*.rb")).each do |f|
        rel = f.delete_prefix("#{path}/")
        next if rel.start_with?("tmp/", "log/", "vendor/", ".git/")

        seeded_file = File.join(seeded_path, rel)
        if !File.file?(seeded_file) || !FileUtils.compare_file(seeded_file, f)
          files << rel
        end
      end
      files.sort
    end

    def check_ruby_syntax(files = nil)
      target_files = files || modified_ruby_files
      target_files = target_files.select { |f| f.end_with?(".rb") }
      return { ok: true, errors: [], output: "" } if target_files.empty?

      errors = []
      ruby_bin = RbConfig.ruby
      target_files.each do |rel|
        full_path = File.join(path, rel)
        next unless File.file?(full_path)

        out, status = Open3.capture2e(child_env, ruby_bin, "-c", full_path)
        unless status.success?
          clean_err = out.gsub("#{path}/", "").strip
          errors << "#{rel}: #{clean_err}"
        end
      end

      { ok: errors.empty?, errors: errors, output: errors.join("\n") }
    end

    def teardown!
      target = work_dir && File.directory?(work_dir) ? work_dir : path
      FileUtils.rm_rf(target) if target && File.exist?(target)
    end
  end
end
