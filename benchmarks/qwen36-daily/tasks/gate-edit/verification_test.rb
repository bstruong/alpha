require "test_helper"

class VerifierTest < ActiveSupport::TestCase
  test "a single draft counts as one leaf" do
    book = Book.create!(title: "Solo", author: "Ada", shared: false, page_count: 1)
    book.drafts.create!(body: "only", superseded: false)

    assert_equal 1, book.leaf_count
  end
end
