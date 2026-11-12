# frozen_string_literal: true

require "test_helper"
require "json"
require "rbconfig"

class IsolationEscapeTest < AlphaTest
  def setup
    Alpha::Isolation.reset_availability!
    skip "bubblewrap unavailable on this host" unless Alpha::Isolation.available?
  end

  def teardown
    Alpha::Isolation.reset_availability!
    FileUtils.rm_rf(@work) if @work && File.directory?(@work)
  end

  def provision_hostile_tree
    @work = Dir.mktmpdir("alpha-isolation-escape-")
    app = File.join(@work, "app")
    seeded = File.join(@work, "seeded")
    FileUtils.mkdir_p(app)
    FileUtils.mkdir_p(seeded)
    FileUtils.mkdir_p(File.join(app, "tmp"))

    File.write(File.join(seeded, "secret.txt"), "SEEDED_SECRET\n")
    File.write(File.join(@work, "solution.patch"), "SOLUTION_PATCH\n")
    File.write(File.join(@work, "verification_test.rb"), "VERIFIER_SECRET\n")

    fake_home = File.join(@work, "fake-home")
    ssh_dir = File.join(fake_home, ".ssh")
    FileUtils.mkdir_p(ssh_dir)
    File.write(File.join(ssh_dir, "id_test"), "HOST_SSH_KEY\n")
    File.write(File.join(fake_home, ".aws_credentials"), "HOST_AWS\n")

    [ app, seeded, fake_home ]
  end

  test "Isolation.available? probes bubblewrap successfully when present" do
    assert Alpha::Isolation.available?
  end

  test "agent cannot read sibling seeded solution verifier or host credentials" do
    app, _seeded, fake_home = provision_hostile_tree
    probe = <<~RUBY
      require "json"
      fake_home = #{fake_home.inspect}
      results = {
        "cwd" => Dir.pwd,
        "seeded" => begin
          File.read("../seeded/secret.txt")
        rescue StandardError => e
          "blocked:\#{e.class}"
        end,
        "solution" => begin
          File.read("../solution.patch")
        rescue StandardError => e
          "blocked:\#{e.class}"
        end,
        "verifier" => begin
          File.read("../verification_test.rb")
        rescue StandardError => e
          "blocked:\#{e.class}"
        end,
        "home_ssh" => begin
          File.read(File.join(Dir.home, ".ssh", "id_test"))
        rescue StandardError => e
          "blocked:\#{e.class}"
        end,
        "host_home" => begin
          File.read(File.join(fake_home, ".aws_credentials"))
        rescue StandardError => e
          "blocked:\#{e.class}"
        end,
        "real_home_ssh" => begin
          File.read(File.join(#{Dir.home.inspect}, ".ssh", "id_rsa"))
        rescue StandardError => e
          "blocked:\#{e.class}"
        end,
        "parent_entries" => begin
          Dir.children("..").sort
        rescue StandardError => e
          ["blocked:\#{e.class}"]
        end,
        "home" => Dir.home,
        "path" => ENV["PATH"].to_s,
        "raw_home_env" => ENV["HOME"].to_s,
        "secret_token" => ENV["SECRET_TOKEN"]
      }
      File.write("tmp/escape-results.json", JSON.pretty_generate(results))
    RUBY
    File.write(File.join(app, "escape_probe.rb"), probe)

    out, status = Alpha::Isolation.run(
      RbConfig.ruby, "escape_probe.rb",
      env: {
        "HOME" => "/tmp/should-be-replaced",
        "PATH" => "/evil/bin:/usr/bin",
        "SECRET_TOKEN" => "should-not-leak",
        "LANG" => "C.UTF-8"
      },
      chdir: app,
      writable_paths: [ app ],
      read_only_paths: [],
      network: false
    )
    assert status.success?, "isolation probe failed: #{out}"

    payload = JSON.parse(File.read(File.join(app, "tmp", "escape-results.json")))
    assert_equal app, payload["cwd"]
    assert_match(/\Ablocked:/, payload["seeded"])
    assert_match(/\Ablocked:/, payload["solution"])
    assert_match(/\Ablocked:/, payload["verifier"])
    assert_match(/\Ablocked:/, payload["home_ssh"])
    assert_match(/\Ablocked:/, payload["host_home"])
    assert_match(/\Ablocked:/, payload["real_home_ssh"])
    assert_nil payload["secret_token"]
    assert_equal [ "app" ], payload["parent_entries"]
    assert_equal Alpha::Isolation::AGENT_HOME, payload["home"]
    assert_equal Alpha::Isolation::AGENT_HOME, payload["raw_home_env"]
    refute_includes payload["path"], "/evil/bin"
    refute_includes File.read(File.join(app, "tmp", "escape-results.json")), "SEEDED_SECRET"
    refute_includes File.read(File.join(app, "tmp", "escape-results.json")), "HOST_SSH_KEY"
  end

  test "agent can write only inside the task app" do
    app, _seeded, _fake_home = provision_hostile_tree
    probe = <<~'RUBY'
      File.write("tmp/inside.txt", "ok")
      begin
        File.write("../outside.txt", "pwn")
        File.write("/tmp/outside-marker.txt", "wrote")
      rescue StandardError
        # expected for ../outside when parent is not host-backed; /tmp is tmpfs
      end
      File.write("tmp/write-probe-done", "1")
    RUBY
    File.write(File.join(app, "write_probe.rb"), probe)

    out, status = Alpha::Isolation.run(
      RbConfig.ruby, "write_probe.rb",
      env: { "LANG" => "C.UTF-8" },
      chdir: app,
      writable_paths: [ app ],
      network: false
    )
    assert status.success?, out
    assert_equal "ok", File.read(File.join(app, "tmp", "inside.txt"))
    refute File.exist?(File.join(@work, "outside.txt")), "agent wrote outside task app on host"
  end

  test "environment allowlist drops unrelated secrets" do
    app, _seeded, _fake_home = provision_hostile_tree
    File.write(File.join(app, "env_probe.rb"), <<~'RUBY')
      require "json"
      File.write("tmp/env.json", JSON.pretty_generate(ENV.to_h))
    RUBY

    out, status = Alpha::Isolation.run(
      RbConfig.ruby, "env_probe.rb",
      env: {
        "OPENAI_API_KEY" => "allowed-key",
        "AWS_SECRET_ACCESS_KEY" => "must-not-appear",
        "SSH_AUTH_SOCK" => "/tmp/ssh.sock",
        "GITHUB_TOKEN" => "must-not-appear",
        "LANG" => "C.UTF-8"
      },
      chdir: app,
      writable_paths: [ app ],
      network: false
    )
    assert status.success?, out
    env = JSON.parse(File.read(File.join(app, "tmp", "env.json")))
    assert_equal "allowed-key", env["OPENAI_API_KEY"]
    refute env.key?("AWS_SECRET_ACCESS_KEY")
    refute env.key?("SSH_AUTH_SOCK")
    refute env.key?("GITHUB_TOKEN")
    assert_equal Alpha::Isolation::AGENT_HOME, env["HOME"]
  end

  test "unavailable sandbox raises and must not fall back" do
    Alpha::Isolation.reset_availability!
    Alpha::Isolation.force_unavailable!
    begin
      err = assert_raises(Alpha::Isolation::UnavailableError) do
        Alpha::Isolation.require_available!
      end
      assert_match(/must not run unsandboxed/i, err.message)

      err2 = assert_raises(Alpha::Isolation::UnavailableError) do
        Alpha::Isolation.wrap(
          [ "true" ],
          env: {},
          chdir: Dir.pwd,
          writable_paths: [ Dir.pwd ]
        )
      end
      assert_match(/unavailable/i, err2.message)
    ensure
      Alpha::Isolation.reset_availability!
    end
  end

  test "Sandbox.agent_env uses empty agent HOME and minimal PATH" do
    app, _seeded, _fake_home = provision_hostile_tree
    sandbox = Alpha::Sandbox.new(path: app, work_dir: @work, seeded_path: File.join(@work, "seeded"))
    env = sandbox.agent_env
    assert_equal Alpha::Isolation::AGENT_HOME, env["HOME"]
    refute_equal Dir.home, env["HOME"]
    assert_includes env["PATH"], File.dirname(RbConfig.ruby)
    refute_includes env["PATH"], "#{Dir.home}/.local/bin" unless File.dirname(RbConfig.ruby).include?("#{Dir.home}/.local")
  end

  test "PiRpc refuses to start when isolation is unavailable" do
    Alpha::Isolation.reset_availability!
    executor = Alpha::Executor::PiRpc.new
    task = Object.new
    task.define_singleton_method(:name) { "isolation-gate" }
    task.define_singleton_method(:prompt) { |_profile| "x" }
    task.define_singleton_method(:thinking) { "low" }

    app, _seeded, _fake_home = provision_hostile_tree
    sandbox = Alpha::Sandbox.new(path: app, work_dir: @work, seeded_path: File.join(@work, "seeded"))
    target = Alpha::InferenceTarget.new(
      base_url: "http://127.0.0.1:8080/v1",
      model_id: "demo",
      engine_preset: "demo"
    )

    Alpha::Isolation.force_unavailable!
    begin
      err = assert_raises(Alpha::Isolation::UnavailableError) do
        executor.call(task: task, sandbox: sandbox, inference_target: target, profile: "shipping")
      end
      assert_match(/must not run unsandboxed/i, err.message)
    ensure
      Alpha::Isolation.reset_availability!
    end
  end

  test "TrialOutcome treats sandbox unavailability as infrastructure-invalid" do
    outcome = Alpha::TrialOutcome.classify(
      exit_reason: "error: Linux namespace sandbox unavailable (bwrap). Evaluated agents must not run unsandboxed",
      timed_out: false,
      agent_patch_empty: true
    )
    assert_equal true, outcome[:invalid]
    assert_equal false, outcome[:scored]
  end
end
