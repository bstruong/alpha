require "test_helper"

class AuditRoleEscalationTest < ActionDispatch::IntegrationTest
  setup do
    @member = Account.create!(name: "Ada", email: "ada-audit@example.com", role: "member")
  end

  test "a member cannot grant a role" do
    patch account_path(@member),
      params: { account: { role: "admin" } },
      headers: { "X-Account-Id" => @member.id },
      as: :json

    assert_equal "member", @member.reload.role
  end
end
