# frozen_string_literal: true

require "test_helper"

class SelfRepairFeedbackTest < ActiveSupport::TestCase
  test "Task prompt includes repair feedback when present" do
    task_dir = File.expand_path("../../scenarios/qwen36-daily/tasks/gate-hello", __dir__)
    task = Alpha::Task.load(task_dir)

    repair_task = task.with_repair_feedback("Expected file HELLO.md to exist, but was not found.")
    prompt = repair_task.prompt("shipping")

    assert_includes prompt, "### Test Failure from Previous Attempt"
    assert_includes prompt, "Expected file HELLO.md to exist, but was not found."
  end

  test "Task supports setting and cloning thinking level" do
    task_dir = File.expand_path("../../scenarios/qwen36-daily/tasks/gate-hello", __dir__)
    task = Alpha::Task.load(task_dir)

    thinking_task = task.with_thinking("high")
    assert_equal "high", thinking_task.thinking
    assert_nil task.thinking
  end

  test "Runner extract_failure_summary extracts formatted failure details" do
    runner = Alpha::Runner.new(scenario: Alpha::Scenario.load("qwen36-daily"))

    detail = {
      rails_test: false,
      rails_output: "Running tests...\nFailure: BooksControllerTest#test_destroy [test/controllers/books_controller_test.rb:42]:\nExpected response to be <302>, but was <403>",
      verifier_ok: false,
      verifier_output: "Run options: --seed 1234\nFailure: VerificationTest#test_book_destroy: Access denied",
      drifted: [ "app/models/user.rb" ]
    }

    summary = runner.send(:extract_failure_summary, detail)
    assert_includes summary, "=== Rails test output ==="
    assert_includes summary, "Expected response to be <302>, but was <403>"
    assert_includes summary, "=== Verification test output ==="
    assert_includes summary, "VerificationTest#test_book_destroy"
    assert_includes summary, "=== Modified protected/forbidden files ==="
    assert_includes summary, "app/models/user.rb"
  end

  test "Report records self-repair and turns metrics" do
    records = [
      {
        task_name: "spec-wins",
        kind: "graded",
        pass: true,
        pass_at_1: false,
        repaired: true,
        turns: 2,
        thinking_level: "high",
        tool_calls: 6,
        prompt_tokens: 4500,
        completion_tokens: 650,
        wall_ms: 25000,
        graders: [ { name: "MinitestFile", pass: true } ]
      }
    ]

    target = Alpha::InferenceTarget.new(
      base_url: "http://192.168.1.92:8080/v1",
      model_id: "qwen36-coder-hybrid",
      engine_preset: "qwen36-coder-hybrid"
    )

    run_id = "test-repair-run-#{Time.now.to_i}"
    res = Alpha::Report.build(
      run_id,
      scenario: "qwen36-daily",
      model_id: "qwen36-coder-hybrid",
      prompt_preset: "shipping",
      inference_target: target,
      task_records: records
    )

    payload = res[:payload]
    assert_equal 1, payload.dig("aggregate", "repaired_count")
    task_out = payload["tasks"].first
    assert_equal true, task_out["repaired"]
    assert_equal 2, task_out["turns"]
    assert_equal "high", task_out["thinking_level"]
    assert_equal false, task_out["pass_at_1"]
    assert_equal true, task_out["pass"]

    markdown = File.read(res[:report_path])
    assert_includes markdown, "Self-Repaired"
    assert_includes markdown, "REPAIRED"

    # Cleanup test files
    FileUtils.rm_rf(File.dirname(res[:summary_path]))
    FileUtils.rm_f(res[:report_path])
  end
end
