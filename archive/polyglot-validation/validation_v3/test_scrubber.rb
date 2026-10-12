require 'minitest/autorun'
require_relative 'pii_scrubber'

class TestPiiScrubber < Minitest::Test
  def setup
    @scrubber = PiiScrubber.new
  end

  def test_scrubs_ssn
    text = "My SSN is 123-45-6789."
    assert_equal "My SSN is [REDACTED_SSN].", @scrubber.scrub(text)
  end

  def test_scrubs_email
    text = "Contact me at bob@example.com."
    assert_equal "Contact me at [REDACTED_EMAIL].", @scrubber.scrub(text)
  end

  def test_preserves_non_pii_numbers
    text = "Order number 123456789."
    assert_equal "Order number 123456789.", @scrubber.scrub(text)
  end
end
