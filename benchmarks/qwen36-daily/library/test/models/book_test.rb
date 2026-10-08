require "test_helper"

class BookTest < ActiveSupport::TestCase
  test "leaf count is the number of drafts" do
    book = Book.create!(title: "Notes", author: "Ada", shared: false, page_count: 1)
    book.drafts.create!(body: "one", superseded: false)
    book.drafts.create!(body: "two", superseded: true)

    assert_equal 2, book.leaf_count
  end
end
