# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require "json"

class PiHarnessTest < AlphaTest
  test "harness pi-monitor is a thin wrapper around the lib monitor" do
    wrapper = File.expand_path("../harness/pi/bin/pi-monitor.rb", __dir__)
    canonical = File.expand_path("../lib/alpha/executor/pi_monitor.rb", __dir__)
    assert File.file?(wrapper), "missing #{wrapper}"
    assert File.file?(canonical), "missing #{canonical}"

    body = File.read(wrapper)
    assert_match(/load canonical/, body)
    refute_match(/def monitor\(/, body, "harness monitor must not re-implement monitor()")
    assert_match(/--max-tool-calls/, File.read(canonical))
  end

  test "PiRpc overlay rewrites models.json baseUrl from InferenceTarget" do
    executor = Alpha::Executor::PiRpc.new
    target = Alpha::InferenceTarget.new(
      base_url: "http://ai.example.test/v1",
      model_id: "glm47-reap",
      engine_preset: "glm47-reap"
    )

    overlay = executor.send(:materialize_harness_overlay, target)
    begin
      models = JSON.parse(File.read(File.join(overlay, "models.json")))
      assert_equal "http://ai.example.test/v1",
                   models.dig("providers", "openai-compatible", "baseUrl")

      settings = JSON.parse(File.read(File.join(overlay, "settings.json")))
      urls = Array(settings.dig("llamaSettings", "servers")).map { |s| s["url"] }
      assert urls.any?, "expected llamaSettings.servers"
      assert urls.all? { |u| u == "http://ai.example.test" }
    ensure
      FileUtils.remove_entry(overlay) if overlay && File.directory?(overlay)
    end
  end

  test "Runner skips repair when turn-1 tool budget is exhausted" do
    scenario = Alpha::Scenario.load("scoped-coding")
    scenario.budget[:max_tool_calls] = 20
    runner = Alpha::Runner.new(
      scenario: scenario,
      inference_target: Alpha::InferenceTarget.new(
        base_url: "http://127.0.0.1:8080/v1",
        model_id: "glm47-reap",
        engine_preset: "glm47-reap"
      )
    )
    task = scenario.tasks.first

    call_count = 0
    fake_exec = Object.new
    fake_exec.define_singleton_method(:call) do |**_kwargs|
      call_count += 1
      Alpha::Executor::Result.new(
        exit_reason: "tool_budget_exceeded",
        timed_out: false,
        wall_ms: 1000,
        tool_calls: 20,
        prompt_tokens: 10,
        completion_tokens: 10,
        log_path: nil
      )
    end

    fake_grader = Object.new
    fake_grader.define_singleton_method(:call) do |**_kwargs|
      Alpha::Grader::Result.new(name: "MinitestFile", pass: false, detail: { error: "still failing" })
    end

    work = Dir.mktmpdir("alpha-budget-test-")
    sandbox = Object.new
    sandbox.define_singleton_method(:path) { File.join(work, "app") }
    sandbox.define_singleton_method(:work_dir) { work }
    sandbox.define_singleton_method(:restore_protected!) { |_task| nil }
    sandbox.define_singleton_method(:diff_from_seeded) { |_patch| nil }
    sandbox.define_singleton_method(:teardown!) { nil }
    FileUtils.mkdir_p(sandbox.path)

    begin
      runner.stub(:resolve_executor, ->(_task) { fake_exec }) do
        runner.stub(:resolve_grader, ->(_task) { fake_grader }) do
          Alpha::Sandbox.stub(:provision, ->(*) { sandbox }) do
            record = runner.send(
              :execute_trial, task, 1, "test-budget-skip-#{Time.now.to_i}",
              keep_sandbox: true, max_turns: 2, thinking: "low"
            )
            assert_equal 1, call_count, "repair turn must not call the executor again"
            assert_equal 1, record[:turns]
            assert_equal false, record[:repaired]
            assert_equal false, record[:pass]
            assert_equal "tool_budget_exceeded", record[:exit_reason]
          end
        end
      end
    ensure
      FileUtils.remove_entry(work) if work && File.directory?(work)
    end
  end
end
