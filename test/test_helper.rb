# frozen_string_literal: true

ENV["ENVIRONMENT"] ||= "test"

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/alpha"

class AlphaTest < Minitest::Test
  # Rails-style `test "name" do ... end` syntax helper for Minitest
  def self.test(name, &block)
    test_name = "test_#{name.gsub(/\s+/, '_')}".to_sym
    defined = method_defined?(test_name)
    raise "#{test_name} is already defined in #{self}" if defined

    if block_given?
      define_method(test_name, &block)
    else
      define_method(test_name) do
        skip "No implementation provided for #{name}"
      end
    end
  end

  # Rails `assert_not` compatibility
  alias_method :assert_not, :refute
end
