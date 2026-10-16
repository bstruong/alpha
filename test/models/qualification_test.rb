require "test_helper"

class QualificationTest < ActiveSupport::TestCase
  test "validates presence of model_id, prompt_preset, and scenario_id" do
    q = Qualification.new
    assert_not q.valid?
    assert_includes q.errors[:model_id], "can't be blank"
    assert_includes q.errors[:prompt_preset], "can't be blank"
    assert_includes q.errors[:scenario_id], "can't be blank"
  end

  test "current? and expired? helpers" do
    active = Qualification.new(
      model_id: "m1",
      prompt_preset: "shipping",
      scenario_id: "s1",
      expires_at: Time.now.utc + 1.day
    )
    assert active.current?
    assert_not active.expired?

    expired = Qualification.new(
      model_id: "m1",
      prompt_preset: "shipping",
      scenario_id: "s1",
      expires_at: Time.now.utc - 1.day
    )
    assert_not expired.current?
    assert expired.expired?
  end
end
