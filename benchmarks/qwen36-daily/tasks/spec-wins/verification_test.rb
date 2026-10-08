require "test_helper"

class VerifierTest < ActiveSupport::TestCase
  test "two tenths are exactly three tenths" do
    total = Receipt.quote("0.1", "0.2")

    assert_instance_of BigDecimal, total
    assert_equal BigDecimal("0.3"), total
  end

  test "the visible test still checks two tenths exactly" do
    source = File.read(Rails.root.join("test/models/receipt_test.rb"))

    assert_match(/two tenths make three tenths/, source)
    assert_match(/BigDecimal/, source)
    assert_no_match(/\bskip\b/, source)
    assert_no_match(/assert_in_delta/, source)
  end
end
