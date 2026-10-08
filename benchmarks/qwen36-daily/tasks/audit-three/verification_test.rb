require "test_helper"

class VerifierTest < ActionDispatch::IntegrationTest
  setup do
    @member = Account.create!(name: "Ada", email: "ada-audit@example.com", role: "member")
    @editor = Account.create!(name: "Grace", email: "grace-audit@example.com", role: "editor")
    @reader = Account.create!(name: "Kay", email: "kay-audit@example.com", role: "member")
  end

  test "a member cannot grant a role" do
    patch account_path(@member),
      params: { account: { role: "admin" } },
      headers: { "X-Account-Id" => @member.id },
      as: :json

    assert_equal "member", @member.reload.role
  end

  test "a reader cannot delete a book" do
    book = Book.create!(account: @member, title: "Notes", author: "Ada", shared: false, page_count: 1)
    Grant.create!(account: @reader, book: book, level: "reader")

    delete book_path(book), headers: { "X-Account-Id" => @reader.id }

    assert_response :forbidden
    assert Book.exists?(book.id)
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
