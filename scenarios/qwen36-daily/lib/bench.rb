# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "yaml"
require "rbconfig"

module Bench
  ROOT = File.expand_path("..", __dir__)
  LIBRARY = File.join(ROOT, "library")
  TASKS = File.join(ROOT, "tasks")
  RESULTS = File.join(ROOT, "results")
  REPORTS = File.join(ROOT, "reports", "reading")
  REPO = File.expand_path("../..", ROOT)
  HARNESS = File.join(REPO, "harness", "pi")
  MODEL = "qwen36-coder"
  SEED = 12_345
  TRIAL_SECONDS = 12 * 60
  ORDER = %w[
    gate-hello gate-boot gate-edit
    empty-card spec-wins library-cache audit-three once-only erase-account
  ].freeze
  SKIP_DIRS = %w[tmp log storage].freeze

  Profile = Data.define(:name, :bullet_cap, :include_invariant) do
    def self.fetch(name)
      case name
      when "shipping"
        new(name, true, true)
      when "measurement"
        new(name, false, false)
      else
        raise "unknown profile #{name.inspect} (shipping or measurement)"
      end
    end
  end

  class Task
    attr_reader :dir, :name, :kind, :expected_seed, :anchor, :restore, :restore_except, :stable_except

    def self.all
      Dir.children(TASKS).sort.filter_map { |name| load(File.join(TASKS, name)) }
    end

    def self.load(dir)
      path = File.join(dir, "task.yml")
      return nil unless File.file?(path)

      data = YAML.safe_load_file(path)
      new(dir, data)
    end

    def initialize(dir, data)
      @dir = dir
      @name = data.fetch("name")
      @kind = data.fetch("kind")
      @expected_seed = data.fetch("expected_seed")
      @anchor = data["anchor"].to_s
      @anchor = nil if @anchor.empty?
      @restore = Array(data["restore"])
      @restore_except = Array(data["restore_except"])
      @stable_except = Array(data["stable_except"])
    end

    def instruction
      File.read(File.join(dir, "instruction.md"))
    end

    def invariant
      path = File.join(dir, "invariant.md")
      File.file?(path) ? File.read(path) : nil
    end

    def environment_patch
      present(File.join(dir, "environment.patch"))
    end

    def solution_patch
      present(File.join(dir, "solution.patch"))
    end

    def verifier
      present(File.join(dir, "verification_test.rb"))
    end

    def prompt(profile)
      parts = [ instruction.strip ]
      parts << invariant.strip if profile.include_invariant && invariant
      parts << <<~NOTE.strip
        The Rails application in the current directory is the code to change.
        Leave bin/rails test green.
      NOTE
      parts.join("\n\n")
    end

    private
      def present(path)
        File.file?(path) && File.size(path).positive? ? path : nil
      end
  end

  module Tree
    module_function

    def copy(dest)
      FileUtils.rm_rf(dest)
      FileUtils.mkdir_p(dest)
      Dir.each_child(LIBRARY) do |name|
        next if SKIP_DIRS.include?(name)

        FileUtils.cp_r(File.join(LIBRARY, name), dest, preserve: true)
      end
      SKIP_DIRS.each { |name| FileUtils.mkdir_p(File.join(dest, name)) }
    end

    def snapshot(app, dest)
      FileUtils.rm_rf(dest)
      FileUtils.mkdir_p(dest)
      Dir.each_child(app) do |name|
        next if SKIP_DIRS.include?(name)

        FileUtils.cp_r(File.join(app, name), dest, preserve: true)
      end
    end

    def apply(app, patch)
      return true unless patch

      _out, status = Open3.capture2(
        "patch", "-p1", "--forward", "--batch", "-d", app, "-i", patch
      )
      status.success?
    end

    def diff(from, to, dest)
      out, status = Open3.capture2("diff", "-ru", from, to)
      raise "diff failed" unless status.success? || status.exitstatus == 1

      body = out.lines.reject { |line| line.include?("/tmp/") && line.start_with?("diff ") }.join
      # diff -ru prints absolute paths. Rewrite them to paths relative to each tree.
      body = body.gsub("#{from}/", "a/").gsub("#{to}/", "b/")
      File.write(dest, body)
      body
    end

    def stable?(snapshot, app, except)
      failures = []
      Dir.glob(File.join(snapshot, "**/*"), File::FNM_DOTMATCH).each do |src|
        next unless File.file?(src)

        rel = src.delete_prefix("#{snapshot}/")
        next if rel.start_with?(".") && rel.count("/") == 0
        next if except.any? { |allowed| rel == allowed }

        dest = File.join(app, rel)
        next if File.file?(dest) && FileUtils.compare_file(src, dest)

        failures << rel
      end
      failures
    end

    def prepare(app)
      env = child_env
      out, status = Open3.capture2e(env, "bin/rails", "db:prepare", chdir: app)
      [ status.success?, out ]
    end

    def rails_test(app)
      env = child_env
      out, status = Open3.capture2e(env, "bin/rails", "test", chdir: app)
      { ok: status.success?, output: out, status: status.exitstatus }
    end

    def verifier(app, task)
      dest = File.join(app, "tmp", "verification_test.rb")
      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.cp(task.verifier, dest)
      out, status = Open3.capture2e(
        child_env, "bundle", "exec", "ruby", "-I#{File.join(app, "test")}", dest, "-v",
        chdir: app
      )
      { ok: status.success?, output: out, status: status.exitstatus, checks: parse_minitest(out) }
    end

    def restore(app, snapshot, task)
      task.restore.each do |rel|
        src = File.join(snapshot, rel)
        dest = File.join(app, rel)
        next unless File.exist?(src)

        FileUtils.rm_rf(dest)
        FileUtils.cp_r(src, dest, preserve: true)
      end
      task.restore_except.each do |rel|
        edited = File.join(app, "tmp", "kept", rel)
        next unless File.file?(edited)

        FileUtils.mkdir_p(File.dirname(File.join(app, rel)))
        FileUtils.cp(edited, File.join(app, rel))
      end
    end

    def keep_excepted(app, task)
      task.restore_except.each do |rel|
        src = File.join(app, rel)
        next unless File.file?(src)

        dest = File.join(app, "tmp", "kept", rel)
        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp(src, dest)
      end
    end

    def child_env
      bindir = File.dirname(RbConfig.ruby)
      {
        "PATH" => "#{bindir}#{File::PATH_SEPARATOR}#{ENV.fetch("PATH", "")}",
        "RAILS_ENV" => "test",
        "BUNDLE_GEMFILE" => File.join(LIBRARY, "Gemfile")
      }
    end

    def parse_minitest(output)
      checks = {}
      output.each_line do |line|
        next unless (match = line.match(/^(\S+) = [\d.]+ s = ([.FE])$/))

        name = match[1]
        checks[name] = match[2] == "." ? "pass" : "fail"
      end
      checks
    end
  end

  module Oracle
    module_function

    def call(only = nil)
      tasks = Task.all.sort_by { |task| ORDER.index(task.name) || ORDER.size }
      tasks.select! { |task| task.name == only } if only
      raise "no task #{only}" if tasks.empty?

      failures = []
      tasks.each do |task|
        ok, detail = check(task)
        puts format("%-16s %s", task.name, detail)
        failures << task.name unless ok
      end
      failures.empty?
    end

    def check(task)
      work = File.join(RESULTS, "oracle", task.name)
      app = File.join(work, "app")
      Tree.copy(app)
      prepared, prepare_out = Tree.prepare(app)
      return [ false, "db:prepare failed\n#{prepare_out}" ] unless prepared

      unless Tree.apply(app, task.environment_patch)
        return [ false, "environment.patch did not apply" ]
      end

      seed = grade(app, task)
      return [ false, "seed reward #{seed[:reward]}, expected #{task.expected_seed}" ] unless seed[:reward] == task.expected_seed

      return [ true, "boot reward 1" ] unless task.solution_patch

      seeded = File.join(work, "seeded")
      Tree.snapshot(app, seeded)
      return [ false, "solution.patch did not apply" ] unless Tree.apply(app, task.solution_patch)

      solved = grade(app, task)
      return [ false, "solution reward #{solved[:reward]}, expected 1\n#{tail(solved)}" ] unless solved[:reward] == 1

      if task.stable_except.any?
        drifted = Tree.stable?(seeded, app, task.stable_except)
        return [ false, "solution touched #{drifted.join(", ")}" ] if drifted.any?
      end

      [ true, "seed #{seed[:reward]} solution 1" ]
    end

    def grade(app, task)
      rails = Tree.rails_test(app)
      hidden = task.verifier ? Tree.verifier(app, task) : nil
      reward = rails[:ok] && (hidden.nil? || hidden[:ok]) ? 1 : 0
      { reward: reward, rails: rails, hidden: hidden }
    end

    def tail(result)
      text = result.dig(:hidden, :output) || result.dig(:rails, :output) || ""
      text.lines.last(30).join
    end
  end

  module Campaign
    module_function

    def call(profile_name, only, trials)
      profile = Profile.fetch(profile_name)
      tasks = Task.all.sort_by { |task| ORDER.index(task.name) || ORDER.size }
      tasks.select! { |task| task.name == only } if only
      raise "no task #{only}" if tasks.empty?

      run_id = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
      run_dir = File.join(RESULTS, "runs", run_id)
      gates_ok = true
      tasks.each do |task|
        if task.kind == "gate" && !gates_ok
          puts "#{task.name}: skipped"
          next
        end

        trials.times do |index|
          result = trial(task, profile, run_dir, index + 1)
          puts format("%-16s trial %d reward %d", task.name, index + 1, result[:reward])
          gates_ok = false if task.kind == "gate" && result[:reward] != 1
        end
        break if task.kind == "gate" && !gates_ok
      end
      puts "results: #{run_dir}"
      gates_ok
    end

    def trial(task, profile, run_dir, index)
      dir = File.join(run_dir, task.name, "trial-#{index}")
      app = File.join(dir, "app")
      Tree.copy(app)
      prepared, prepare_out = Tree.prepare(app)
      raise "#{task.name}: db:prepare failed\n#{prepare_out}" unless prepared
      raise "#{task.name}: environment.patch did not apply" unless Tree.apply(app, task.environment_patch)

      seeded = File.join(dir, "seeded")
      Tree.snapshot(app, seeded)
      log = File.join(dir, "agent.log")
      timed_out = task.name == "gate-boot" ? false : drive(app, task, profile, log)
      Tree.keep_excepted(app, task)
      Tree.restore(app, seeded, task)
      patch = File.join(dir, "agent.patch")
      body = Tree.diff(seeded, app, patch)
      graded = Oracle.grade(app, task)
      recalled = task.anchor ? body.match?(Regexp.new(task.anchor)) : nil
      drifted = Tree.stable?(seeded, app, task.stable_except)
      record = {
        task: task.name,
        profile: profile.name,
        trial: index,
        reward: graded[:reward],
        recalled: recalled,
        timed_out: timed_out,
        stable: drifted.empty?,
        rails_test: graded.dig(:rails, :ok),
        checks: graded.dig(:hidden, :checks) || {},
        profile_digest: digest(profile, task)
      }
      File.write(File.join(dir, "result.json"), JSON.pretty_generate(record))
      File.write(File.join(dir, "rails_test.log"), graded.dig(:rails, :output).to_s)
      File.write(File.join(dir, "verifier.log"), graded.dig(:hidden, :output).to_s)
      record
    end

    def drive(app, task, profile, log)
      FileUtils.mkdir_p(File.dirname(log))
      cmd, env = command(app, task, profile, log)
      pid = Process.spawn(env, *cmd, chdir: app, pgroup: true)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TRIAL_SECONDS
      timed_out = false
      loop do
        _pid, status = Process.wait2(pid, Process::WNOHANG)
        break if status
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          timed_out = true
          Process.kill("-TERM", pid) rescue nil
          Process.wait2(pid) rescue nil
          break
        end
        sleep 0.5
      end
      timed_out
    end

    def command(app, task, profile, log)
      prompt = task.prompt(profile)
      env = Tree.child_env.merge(
        "PI_CODING_AGENT_DIR" => HARNESS,
        "LLAMA_SERVER_URL" => ENV.fetch("LLAMA_SERVER_URL", "http://127.0.0.1:8080"),
        "LLAMA_BASE_URL" => ENV.fetch("LLAMA_BASE_URL", "http://127.0.0.1:8080"),
        "OPENAI_API_BASE" => ENV.fetch("OPENAI_API_BASE", "http://127.0.0.1:8080/v1"),
        "PI_BIN" => File.join(HARNESS, "node_modules", ".bin", "pi")
      )
      if profile.name == "shipping"
        monitor = File.join(HARNESS, "bin", "pi-monitor.rb")
        cmd = [
          RbConfig.ruby, monitor, "--log-file", log, "--",
          "--print", "--provider", "openai-compatible", "--model", MODEL,
          "--thinking", "low", "--approve", "--no-session",
          "--append-system-prompt", File.join(HARNESS, "SYSTEM.md"),
          prompt
        ]
      else
        env["BENCH_MODEL"] = MODEL
        cmd = [ "miniswen", "-p", prompt ]
      end
      [ cmd, env ]
    end

    def digest(profile, task)
      payload = [
        profile.name,
        MODEL,
        SEED.to_s,
        TRIAL_SECONDS.to_s,
        File.read(File.join(HARNESS, "SYSTEM.md")),
        task.instruction,
        task.invariant.to_s
      ].join("\n")
      Digest::SHA256.hexdigest(payload)[0, 16]
    end
  end

  module Packet
    module_function

    def call
      runs = Dir.glob(File.join(RESULTS, "runs", "*")).select { |path| File.directory?(path) }.sort
      raise "no runs under #{RESULTS}/runs" if runs.empty?

      run = runs.last
      FileUtils.mkdir_p(REPORTS)
      Task.all.each do |task|
        trials = Dir.glob(File.join(run, task.name, "trial-*", "result.json")).sort
        next if trials.empty?

        dir = File.join(REPORTS, task.name)
        FileUtils.rm_rf(dir)
        FileUtils.mkdir_p(dir)
        FileUtils.cp(File.join(task.dir, "instruction.md"), dir)
        FileUtils.cp(task.solution_patch, File.join(dir, "solution.patch")) if task.solution_patch
        FileUtils.cp(task.verifier, File.join(dir, "verification_test.rb")) if task.verifier

        parsed = trials.map { |path| JSON.parse(File.read(path)).merge("path" => path) }
        write_example(dir, parsed, "pass")
        write_example(dir, parsed, "fail")
        lines = parsed.map { |row| "trial #{row["trial"]}: reward #{row["reward"]} recalled #{row["recalled"].inspect}" }
        File.write(File.join(dir, "recall.txt"), lines.join("\n") + "\n")
        puts task.name
      end
      puts "packets: #{REPORTS}"
      true
    end

    def write_example(dir, parsed, kind)
      row = parsed.find { |item| kind == "pass" ? item["reward"] == 1 : item["reward"] != 1 }
      return unless row

      patch = File.join(File.dirname(row["path"]), "agent.patch")
      FileUtils.cp(patch, File.join(dir, "#{kind}.patch")) if File.file?(patch)
    end
  end

  module PythonTraps
    module_function

    def call
      script = File.join(REPO, "scripts", "run_module2_spec_traps.py")
      env = Tree.child_env.merge("BENCH_MODEL" => MODEL, "PYTHONUNBUFFERED" => "1")
      system(env, "python3", script, chdir: REPO)
    end
  end

  module CLI
    module_function

    def call(argv)
      command = argv.shift || "help"
      case command
      when "oracle"
        Oracle.call(argv[0]) ? 0 : 1
      when "run"
        profile, task, trials = parse_run(argv)
        Campaign.call(profile, task, trials) ? 0 : 1
      when "packet"
        Packet.call ? 0 : 1
      when "python"
        PythonTraps.call ? 0 : 1
      else
        puts help
        command == "help" ? 0 : 1
      end
    rescue StandardError => error
      warn error.message
      1
    end

    def parse_run(argv)
      profile = "shipping"
      task = nil
      trials = 3
      while (arg = argv.shift)
        case arg
        when "--profile" then profile = argv.shift
        when "--task" then task = argv.shift
        when "--trials" then trials = Integer(argv.shift)
        else raise "unknown argument #{arg}"
        end
      end
      [ profile, task, trials ]
    end

    def help
      <<~HELP
        bench oracle [task]              Seed scores expected_seed, solution scores 1. No model.
        bench run [--profile shipping] [--task NAME] [--trials 3]
                                          Shipping uses Pi. measurement uses miniswen.
        bench packet                      Reading packet from the latest run into reports/reading.
        bench python                      Python spec traps, one existing module, model qwen36-coder.
      HELP
    end
  end
end
