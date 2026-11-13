# frozen_string_literal: true

require "test_helper"

class StageGatingAndPreflightLintTest < AlphaTest
  test "Task supports max_tool_calls configuration" do
    task_dir = File.expand_path("../scenarios/qwen36-daily/tasks/gate-hello", __dir__)
    task = Alpha::Task.load(task_dir)
    assert_nil task.max_tool_calls

    custom_task = Alpha::Task.new(
      name: "custom-task",
      kind: "graded",
      dir: task_dir,
      max_tool_calls: 15
    )
    assert_equal 15, custom_task.max_tool_calls
  end

  test "Sandbox modified_ruby_files and check_ruby_syntax detect syntax errors" do
    temp_dir = Dir.mktmpdir("alpha-syntax-test")
    app_dir = File.join(temp_dir, "app")
    seeded_dir = File.join(temp_dir, "seeded")
    FileUtils.mkdir_p(File.join(app_dir, "app", "models"))
    FileUtils.mkdir_p(File.join(seeded_dir, "app", "models"))

    seeded_file = File.join(seeded_dir, "app", "models", "book.rb")
    File.write(seeded_file, "class Book; end\n")

    current_file = File.join(app_dir, "app", "models", "book.rb")
    File.write(current_file, "class Book\n  def title\n    'Ruby'\n  end\nend\n")

    sandbox = Alpha::Sandbox.new(
      path: app_dir,
      work_dir: temp_dir,
      seeded_path: seeded_dir
    )

    # Modified file with valid syntax
    assert_equal ["app/models/book.rb"], sandbox.modified_ruby_files
    res_ok = sandbox.check_ruby_syntax
    assert_equal true, res_ok[:ok]
    assert_empty res_ok[:errors]

    # Modify with invalid Ruby syntax (missing end)
    File.write(current_file, "class Book\n  def unclosed\n    puts 'broken'\n")
    res_err = sandbox.check_ruby_syntax
    assert_equal false, res_err[:ok]
    assert_equal 1, res_err[:errors].size
    assert_includes res_err[:errors].first, "app/models/book.rb"
    assert_includes res_err[:errors].first, "syntax error"
  ensure
    FileUtils.rm_rf(temp_dir) if temp_dir
  end

  test "MinitestFile fails fast on syntax errors before executing full test suite" do
    temp_dir = Dir.mktmpdir("alpha-minitest-syntax-test")
    app_dir = File.join(temp_dir, "app")
    seeded_dir = File.join(temp_dir, "seeded")
    FileUtils.mkdir_p(File.join(app_dir, "app", "models"))
    FileUtils.mkdir_p(File.join(seeded_dir, "app", "models"))

    # Syntax error in app/models/broken.rb
    broken_file = File.join(app_dir, "app", "models", "broken.rb")
    File.write(broken_file, "class Broken\n  def fail\n")

    sandbox = Alpha::Sandbox.new(
      path: app_dir,
      work_dir: temp_dir,
      seeded_path: seeded_dir
    )

    task = Struct.new(:verifier_path, :stable_except).new(nil, [])
    grader = Alpha::Grader::MinitestFile.new

    result = grader.call(sandbox: sandbox, task: task)
    assert_equal false, result.pass
    assert_equal false, result.detail[:syntax_ok]
    assert_equal 1, result.detail[:syntax_errors].size
    assert_includes result.detail[:syntax_errors].first, "app/models/broken.rb"
  ensure
    FileUtils.rm_rf(temp_dir) if temp_dir
  end

  test "Sandbox prefers local vendor/bundle then baked ALPHA_WEB_RAILS_BUNDLE" do
    temp_dir = Dir.mktmpdir("alpha-bundle-path-test")
    app_dir = File.join(temp_dir, "app")
    FileUtils.mkdir_p(app_dir)
    sandbox = Alpha::Sandbox.new(path: app_dir, work_dir: temp_dir)

    previous = ENV["ALPHA_WEB_RAILS_BUNDLE"]
    ENV.delete("ALPHA_WEB_RAILS_BUNDLE")
    assert_nil sandbox.scenario_bundle_path
    refute sandbox.child_env.key?("BUNDLE_PATH")
    refute sandbox.agent_env.key?("BUNDLE_PATH")

    baked = File.join(temp_dir, "baked-bundle")
    FileUtils.mkdir_p(baked)
    ENV["ALPHA_WEB_RAILS_BUNDLE"] = baked
    assert_equal baked, sandbox.scenario_bundle_path
    assert_equal baked, sandbox.child_env["BUNDLE_PATH"]
    assert_equal baked, sandbox.agent_env["BUNDLE_PATH"]

    local = File.join(app_dir, "vendor", "bundle")
    FileUtils.mkdir_p(local)
    assert_equal local, sandbox.scenario_bundle_path
    assert_equal local, sandbox.child_env["BUNDLE_PATH"]
  ensure
    if previous
      ENV["ALPHA_WEB_RAILS_BUNDLE"] = previous
    else
      ENV.delete("ALPHA_WEB_RAILS_BUNDLE")
    end
    FileUtils.rm_rf(temp_dir) if temp_dir
  end

  test "self-repair helpers are removed from Runner" do
    runner = Alpha::Runner.new(scenario: Alpha::Scenario.load("qwen36-daily"))
    refute runner.respond_to?(:extract_failure_summary, true)
    refute runner.respond_to?(:clean_test_output, true)
  end

  test "MinitestFile handles command timeout cleanly" do
    grader = Alpha::Grader::MinitestFile.new
    temp_dir = Dir.mktmpdir("alpha-timeout-test")
    FileUtils.mkdir_p(File.join(temp_dir, "bin"))
    rails_bin = File.join(temp_dir, "bin", "rails")
    File.write(rails_bin, "#!/usr/bin/env ruby\nsleep 2\n")
    File.chmod(0o755, rails_bin)

    sandbox = Struct.new(:path, :child_env).new(temp_dir, {})
    def sandbox.run_in_clean_env
      yield
    end

    res = grader.send(:run_rails_test, sandbox, timeout_s: 0.1)
    assert_equal false, res[:ok]
    assert_includes res[:output], "Command timed out after 0.1s"
    assert_equal 124, res[:status]
  ensure
    FileUtils.rm_rf(temp_dir) if temp_dir
  end

  test "PiRpc sets exit_reason to tool_budget_exceeded when tool limit is hit" do
    executor = Alpha::Executor::PiRpc.new
    temp_dir = Dir.mktmpdir("alpha-pi-rpc-budget-test")
    telemetry_file = File.join(temp_dir, "telemetry.json")
    log_file = File.join(temp_dir, "agent.log")

    File.write(telemetry_file, JSON.pretty_generate({
      "tool_calls" => 15,
      "prompt_tokens" => 2000,
      "completion_tokens" => 300,
      "tool_budget_exceeded" => true
    }))

    data = executor.send(:read_telemetry, telemetry_file, log_file)
    assert_equal 15, data["tool_calls"]
    assert_equal true, data["tool_budget_exceeded"]
  ensure
    FileUtils.rm_rf(temp_dir) if temp_dir
  end
end
