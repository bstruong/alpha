require "test_helper"

class AlphaHarnessTest < AlphaTest
  test "loads Task from directory" do
    task_dir = File.expand_path("../scenarios/qwen36-daily/tasks/gate-hello", __dir__)
    task = Alpha::Task.load(task_dir)

    assert_equal "gate-hello", task.name
    assert_equal "gate", task.kind
    assert task.gate?
    assert_includes task.instruction, "HELLO.md"
    assert_includes task.prompt("shipping"), "Leave bin/rails test green"
  end

  test "loads Scenario and tasks in order" do
    scenario = Alpha::Scenario.load("qwen36-daily")

    assert_equal "qwen36-daily", scenario.id
    assert_equal "shipping", scenario.profile.name
    # shipping max_rung L2 excludes audit-three (L3)
    assert_equal 8, scenario.tasks.size
    assert_equal "gate-hello", scenario.tasks.first.name
    assert_equal "erase-account", scenario.tasks.last.name
    assert scenario.tasks.none? { |t| t.name == "audit-three" }

    measurement = Alpha::Scenario.load("qwen36-daily", profile: "measurement")
    assert measurement.tasks.any? { |t| t.name == "audit-three" }
  end

  test "builds Report and renders markdown and JSON" do
    records = [
      {
        task_name: "gate-hello",
        kind: "gate",
        pass: true,
        pass_at_1: true,
        tool_calls: 3,
        prompt_tokens: 1200,
        completion_tokens: 150,
        wall_ms: 12000,
        graders: [ { name: "MinitestFile", pass: true } ]
      }
    ]

    target = Alpha::InferenceTarget.new(
      base_url: "http://127.0.0.1:8080/v1",
      model_id: "qwen36-coder-hybrid",
      engine_preset: "qwen36-coder-hybrid"
    )

    run_id = "test-run-#{Time.now.to_i}"
    res = Alpha::Report.build(
      run_id,
      scenario: "qwen36-daily",
      model_id: "qwen36-coder-hybrid",
      prompt_preset: "shipping",
      inference_target: target,
      task_records: records
    )

    assert File.file?(res[:summary_path])
    assert File.file?(res[:report_path])

    payload = JSON.parse(File.read(res[:summary_path]))
    assert_equal "alpha.report.v2", payload["schema"]
    assert_equal 1.0, payload.dig("aggregate", "pass_at_1")
    assert payload.dig("aggregate").key?("failure_class_histogram")
    assert payload.dig("aggregate").key?("credit_mean")

    # Cleanup temporary test artifacts
    FileUtils.rm_rf(File.dirname(res[:summary_path]))
    FileUtils.rm_f(res[:report_path])
  end

  test "Report includes latency budget and workflow fit when tasks declare budgets" do
    target = Alpha::InferenceTarget.new(
      base_url: "http://127.0.0.1:8080/v1",
      model_id: "gemma4-4b",
      engine_preset: "gemma4-4b"
    )
    records = [
      {
        task_name: "prioritize-attention",
        kind: "graded",
        pass: true,
        pass_at_1: true,
        repaired: false,
        turns: 1,
        tool_calls: 0,
        prompt_tokens: 10,
        completion_tokens: 20,
        wall_ms: 1200,
        latency_budget_ms: 3000,
        workflow_tier: "interactive",
        within_budget: true,
        graders: []
      },
      {
        task_name: "draft-outreach",
        kind: "graded",
        pass: true,
        pass_at_1: true,
        repaired: false,
        turns: 1,
        tool_calls: 0,
        prompt_tokens: 10,
        completion_tokens: 40,
        wall_ms: 20_000,
        latency_budget_ms: 15_000,
        workflow_tier: "assistive",
        within_budget: false,
        graders: []
      }
    ]

    run_id = "test-latency-#{Time.now.to_i}"
    res = Alpha::Report.build(
      run_id,
      scenario: "ikigai-dot",
      model_id: "gemma4-4b",
      prompt_preset: "shipping",
      inference_target: target,
      task_records: records
    )

    payload = JSON.parse(File.read(res[:summary_path]))
    assert_equal 2, payload.dig("aggregate", "latency_budgeted_tasks")
    assert_equal 1, payload.dig("aggregate", "latency_within_budget")
    assert_equal 1, payload.dig("aggregate", "workflow_fit", "interactive")
    assert_equal 1, payload.dig("aggregate", "workflow_fit", "unusable")
    md = File.read(res[:report_path])
    assert_match(/Capability summary/, md)
    assert_match(/Latency within budget/, md)
    assert_match(/Wall \(s\)/, md)
    assert_match(/alpha\.report\.v2/, md)

    FileUtils.rm_rf(File.dirname(res[:summary_path]))
    FileUtils.rm_f(res[:report_path])
  end

  test "InferenceTarget parses engine/models.ini correctly" do
    ini_path = File.expand_path("../engine/models.ini", __dir__)
    sections = Alpha::InferenceTarget.parse_ini(ini_path)

    assert sections.key?("*")
    assert sections.key?("qwen36-coder")
    assert sections.key?("qwen36-coder-hybrid")
    assert sections.key?("glm47-reap")
    assert_equal "262144", sections["qwen36-coder"]["ctx-size"]
  end

  test "Runner dry_run is planning-only with no scored trials" do
    scenario = Alpha::Scenario.load("qwen36-daily", only_task: "gate-hello")
    runner = Alpha::Runner.new(scenario: scenario, suite_complete: false)

    res = nil
    assert_output do
      res = runner.call(dry_run: true)
    end
    assert res[:ok]
    assert File.file?(res[:report][:summary_path])
    payload = JSON.parse(File.read(res[:report][:summary_path]))
    assert_equal true, payload["dry_run"]
    assert_equal false, payload["suite_complete"]
    assert_equal false, payload["qualification_eligible"]
    assert_empty payload["tasks"]
    assert_equal "planning_only", payload.dig("status", "execution_health")
    assert_equal "none", payload.dig("status", "routing_authority")
    assert_equal 0, payload.dig("aggregate", "tasks_total")

    # Cleanup artifacts
    FileUtils.rm_rf(File.dirname(res[:report][:summary_path]))
    FileUtils.rm_f(res[:report][:report_path])
  end

  test "Report First-attempt success counts pass_at_1 with exact numerator and denominator" do
    records = [
      {
        task_name: "a", kind: "graded", pass: true, pass_at_1: true, scored: true, invalid: false,
        credit: 1.0, failure_class: "none", tool_calls: 0, wall_ms: 1, graders: []
      },
      {
        task_name: "b", kind: "graded", pass: true, pass_at_1: false, scored: true, invalid: false,
        credit: 1.0, failure_class: "none", tool_calls: 0, wall_ms: 1, graders: []
      },
      {
        task_name: "c", kind: "graded", pass: false, pass_at_1: false, scored: false, invalid: true,
        credit: 0.0, failure_class: "infra", tool_calls: 0, wall_ms: 1, graders: []
      }
    ]
    target = Alpha::InferenceTarget.new(
      base_url: "http://127.0.0.1:8080/v1",
      model_id: "qwen36-coder-hybrid",
      engine_preset: "qwen36-coder-hybrid"
    )
    run_id = "test-pass-at-1-agg-#{Time.now.to_i}"
    res = Alpha::Report.build(
      run_id,
      scenario: "qwen36-daily",
      model_id: "qwen36-coder-hybrid",
      prompt_preset: "shipping",
      inference_target: target,
      task_records: records,
      suite_complete: true
    )
    agg = res[:payload]["aggregate"]
    assert_equal 1, agg["pass_at_1_numerator"]
    assert_equal 2, agg["pass_at_1_denominator"]
    assert_in_delta 0.5, agg["pass_at_1"], 0.001
    assert_equal 1, agg["invalid_trials"]
    assert_equal "infrastructure_invalid", res[:payload].dig("status", "execution_health")
    assert_equal false, res[:payload]["qualification_eligible"]

    FileUtils.rm_rf(File.dirname(res[:summary_path]))
    FileUtils.rm_f(res[:report_path])
  end
end
