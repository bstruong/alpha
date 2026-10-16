require "test_helper"

class VerifierTest < ActiveSupport::TestCase
  test "HELLO.md is exactly the greeting" do
    assert_equal "Hello, world\n", File.read(Rails.root.join("HELLO.md"))
  end
end
