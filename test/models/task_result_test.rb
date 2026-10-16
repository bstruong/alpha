require "test_helper"

class TaskResultTest < ActiveSupport::TestCase
  setup do
    @eval_run = EvalRun.create!(run_id: "run-test", scenario_id: "s1", model_id: "m1", status: "completed")
  end

  test "validates presence of task_name" do
    tr = TaskResult.new(eval_run: @eval_run)
    assert_not tr.valid?
    assert_includes tr.errors[:task_name], "can't be blank"
  end

  test "passed? helper" do
    tr1 = TaskResult.new(eval_run: @eval_run, task_name: "t1", pass: true)
    assert tr1.passed?

    tr2 = TaskResult.new(eval_run: @eval_run, task_name: "t2", pass: false)
    assert_not tr2.passed?
  end
end
