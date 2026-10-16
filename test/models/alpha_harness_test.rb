require "test_helper"

class AlphaHarnessTest < ActiveSupport::TestCase
  test "loads Task from directory" do
    task_dir = File.expand_path("../../scenarios/qwen36-daily/tasks/gate-hello", __dir__)
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
    assert_equal 9, scenario.tasks.size
    assert_equal "gate-hello", scenario.tasks.first.name
    assert_equal "erase-account", scenario.tasks.last.name
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
      base_url: "http://192.168.1.92:8080/v1",
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
    assert_equal "alpha.report.v1", payload["schema"]
    assert_equal 1.0, payload.dig("aggregate", "pass_at_1")

    # Cleanup temporary test artifacts
    FileUtils.rm_rf(File.dirname(res[:summary_path]))
    FileUtils.rm_f(res[:report_path])
  end

  test "InferenceTarget parses engine/models.ini correctly" do
    ini_path = File.expand_path("../../engine/models.ini", __dir__)
    sections = Alpha::InferenceTarget.parse_ini(ini_path)

    assert sections.key?("*")
    assert sections.key?("qwen36-coder")
    assert sections.key?("qwen36-coder-hybrid")
    assert sections.key?("glm47-reap")
    assert_equal "262144", sections["qwen36-coder"]["ctx-size"]
  end

  test "InferenceTarget generates expected preset_args" do
    qwen_args = Alpha::InferenceTarget.preset_args("qwen36-coder-hybrid")
    assert_includes qwen_args, "/models/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf"
    assert_includes qwen_args, "qwen36-coder-hybrid,qwen36-coder"
    assert_includes qwen_args, "262144"

    glm_args = Alpha::InferenceTarget.preset_args("glm47-reap")
    assert_includes glm_args, "/models/GLM-4.7-Flash-REAP-23B-A3B-Q4_K_M.gguf"
    assert_includes glm_args, "glm47-reap"
    assert_includes glm_args, "131072"
    assert_includes glm_args, "--cpu-moe"
  end

  test "InferenceTarget responds to lifecycle methods" do
    assert_respond_to Alpha::InferenceTarget, :engine_up
    assert_respond_to Alpha::InferenceTarget, :engine_down!
    assert_respond_to Alpha::InferenceTarget, :engine_status
    assert_respond_to Alpha::InferenceTarget, :local_kubectl?

    target = Alpha::InferenceTarget.from_engine("qwen36-coder-hybrid")
    assert_respond_to target, :ping_health
    assert_respond_to target, :ensure_awake!
    assert_respond_to target, :server_root_url
  end
end
