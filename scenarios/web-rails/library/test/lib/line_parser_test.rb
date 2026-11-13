# frozen_string_literal: true

require "test_helper"

class LineParserTest < ActiveSupport::TestCase
  test "parses keys ignoring comments and blanks" do
    text = <<~CFG
      # comment
      FOO=1

      BAR = two
      FOO=3
    CFG
    assert_equal({ "FOO" => "3", "BAR" => "two" }, LineParser.parse(text))
  end
end
