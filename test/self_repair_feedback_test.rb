# frozen_string_literal: true

require "test_helper"

class SelfRepairFeedbackTest < AlphaTest
  test "Task supports setting and cloning thinking level" do
    task_dir = File.expand_path("../scenarios/qwen36-daily/tasks/gate-hello", __dir__)
    task = Alpha::Task.load(task_dir)

    thinking_task = task.with_thinking("high")
    assert_equal "high", thinking_task.thinking
    assert_nil task.thinking
  end

  test "Task prompt does not include repair feedback sections" do
    task_dir = File.expand_path("../scenarios/qwen36-daily/tasks/gate-hello", __dir__)
    task = Alpha::Task.load(task_dir)
    prompt = task.prompt("shipping")

    refute_includes prompt, "### Test Failure from Previous Attempt"
    refute_respond_to task, :with_repair_feedback
  end

  test "Report aggregate First-attempt success uses pass_at_1 not final pass" do
    records = [
      {
        task_name: "spec-wins",
        kind: "graded",
        pass: true,
        pass_at_1: false,
        credit: 1.0,
        scored: true,
        invalid: false,
        failure_class: "none",
        thinking_level: "high",
        tool_calls: 6,
        prompt_tokens: 4500,
        completion_tokens: 650,
        wall_ms: 25000,
        graders: [ { name: "MinitestFile", pass: true } ]
      },
      {
        task_name: "empty-card",
        kind: "graded",
        pass: true,
        pass_at_1: true,
        credit: 1.0,
        scored: true,
        invalid: false,
        failure_class: "none",
        thinking_level: "low",
        tool_calls: 2,
        prompt_tokens: 100,
        completion_tokens: 20,
        wall_ms: 1000,
        graders: [ { name: "MinitestFile", pass: true } ]
      }
    ]

    target = Alpha::InferenceTarget.new(
      base_url: "http://127.0.0.1:8080/v1",
      model_id: "qwen36-coder-hybrid",
      engine_preset: "qwen36-coder-hybrid"
    )

    run_id = "test-first-attempt-#{Time.now.to_i}"
    res = Alpha::Report.build(
      run_id,
      scenario: "qwen36-daily",
      model_id: "qwen36-coder-hybrid",
      prompt_preset: "shipping",
      inference_target: target,
      task_records: records
    )

    payload = res[:payload]
    assert_equal 1, payload.dig("aggregate", "pass_at_1_numerator")
    assert_equal 2, payload.dig("aggregate", "pass_at_1_denominator")
    assert_in_delta 0.5, payload.dig("aggregate", "pass_at_1"), 0.001
    refute payload.dig("aggregate").key?("repaired_count")
    refute payload.dig("aggregate").key?("pass_final")

    markdown = File.read(res[:report_path])
    assert_includes markdown, "First-attempt success"
    refute_includes markdown, "Self-Repaired"
    refute_includes markdown, "REPAIRED"

    FileUtils.rm_rf(File.dirname(res[:summary_path]))
    FileUtils.rm_f(res[:report_path])
  end
end
