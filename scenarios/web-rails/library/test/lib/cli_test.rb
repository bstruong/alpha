# frozen_string_literal: true

require "test_helper"

class CliTest < ActiveSupport::TestCase
  test "greets name" do
    result = Cli.parse([ "Ada" ])
    assert_equal 0, result[:exit]
    assert_equal "hello Ada", result[:message]
  end

  test "missing name exits 1" do
    result = Cli.parse([])
    assert_equal 1, result[:exit]
  end

  test "unknown flag exits 2" do
    result = Cli.parse([ "--nope", "Ada" ])
    assert_equal 2, result[:exit]
  end
end
