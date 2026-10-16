require "test_helper"

class BookDeleteTest < ActionDispatch::IntegrationTest
  test "an editor deletes a book they can edit" do
    owner = Account.create!(name: "Ada", email: "ada-owner@example.com")
    editor = Account.create!(name: "Grace", email: "grace-editor@example.com", role: "editor")
    book = Book.create!(account: owner, title: "Notes", author: "Ada", shared: false, page_count: 1)
    Grant.create!(account: editor, book: book, level: "editor")
    delete book_path(book), headers: { "X-Account-Id" => editor.id }

    assert_response :no_content
    assert_not Book.exists?(book.id)
  end
end
