require "test_helper"

class EvalRunTest < ActiveSupport::TestCase
  test "validates presence of run_id, scenario_id, model_id, and status" do
    run = EvalRun.new
    assert_not run.valid?
    assert_includes run.errors[:run_id], "can't be blank"
    assert_includes run.errors[:scenario_id], "can't be blank"
    assert_includes run.errors[:model_id], "can't be blank"
    assert_includes run.errors[:status], "can't be blank"
  end

  test "validates status inclusion" do
    run = EvalRun.new(run_id: "test-run", scenario_id: "s1", model_id: "m1", status: "invalid")
    assert_not run.valid?
    assert_includes run.errors[:status], "is not included in the list"

    run.status = "completed"
    assert run.valid?
  end

  test "has_many task_results" do
    run = EvalRun.create!(run_id: "run-with-tasks", scenario_id: "s1", model_id: "m1", status: "completed")
    task = run.task_results.create!(task_name: "gate-hello", pass: true)
    assert_equal 1, run.task_results.count
    assert_equal task, run.task_results.first
  end
end
