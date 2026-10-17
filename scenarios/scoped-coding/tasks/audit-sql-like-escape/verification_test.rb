require "test_helper"

class AuditSqlLikeEscapeTest < ActionDispatch::IntegrationTest
  setup do
    @member = Account.create!(name: "Ada", email: "ada-audit@example.com", role: "member")
  end

  test "a percent sign is data, not a wildcard for every title" do
    Book.create!(account: @member, title: "Save 50% off", author: "Ada", shared: true, page_count: 1)
    Book.create!(account: @member, title: "Handbook", author: "Ada", shared: true, page_count: 1)

    percent = BookSearch.call(@member, "%").pluck(:title)
    exact = BookSearch.call(@member, "50%").pluck(:title)
    underscore = BookSearch.call(@member, "_").pluck(:title)

    assert_equal [ "Save 50% off" ], percent
    assert_equal [ "Save 50% off" ], exact
    assert_empty underscore
  end
end
