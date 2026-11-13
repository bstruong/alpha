# frozen_string_literal: true

require "test_helper"

class MoneyCentsTest < ActiveSupport::TestCase
  test "half-up rounding to cents" do
    assert_equal 100, MoneyCents.round_dollars("1.00")
    assert_equal 105, MoneyCents.round_dollars("1.045")
    assert_equal 104, MoneyCents.round_dollars("1.044")
  end
end
