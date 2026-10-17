require "test_helper"

class AuditBookDestroyTest < ActionDispatch::IntegrationTest
  setup do
    @member = Account.create!(name: "Ada", email: "ada-audit@example.com", role: "member")
    @reader = Account.create!(name: "Kay", email: "kay-audit@example.com", role: "member")
  end

  test "a reader cannot delete a book" do
    book = Book.create!(account: @member, title: "Notes", author: "Ada", shared: false, page_count: 1)
    Grant.create!(account: @reader, book: book, level: "reader")

    delete book_path(book), headers: { "X-Account-Id" => @reader.id }

    assert_response :forbidden
    assert Book.exists?(book.id)
  end
end
