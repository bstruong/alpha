require "test_helper"

class AccountUpdateTest < ActionDispatch::IntegrationTest
  test "a member changes their own name" do
    account = Account.create!(name: "Ada", email: "ada-update@example.com", role: "member")

    patch account_path(account),
      params: { account: { name: "Ada Lovelace" } },
      headers: { "X-Account-Id" => account.id },
      as: :json

    assert_response :success
    assert_equal "Ada Lovelace", account.reload.name
    assert_equal "member", account.role
  end
end
