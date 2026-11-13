# frozen_string_literal: true

require "test_helper"

class FixCliArgsVerification < ActiveSupport::TestCase
  test "tool binary greets" do
    out = `#{Rails.root.join("bin/tool")} Ada`
    assert_equal 0, $?.exitstatus
    assert_equal "hello Ada\n", out
  end

  test "missing name exits 1" do
    `#{Rails.root.join("bin/tool")}`
    assert_equal 1, $?.exitstatus
  end
end
