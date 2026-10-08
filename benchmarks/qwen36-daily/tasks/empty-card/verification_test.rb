require "test_helper"

class VerifierTest < ActiveSupport::TestCase
  test "a card with no books still loads and totals to zero" do
    card = LibraryCard.load_legacy("title" => "Empty", "author" => "Ada", "books" => [])

    assert_equal({ title: "Empty", author: "Ada", leaf_count: 0 }, card)
  end

  test "a missing author is blank" do
    card = LibraryCard.load_legacy("title" => "Unsigned", "books" => [ { "leaf_count" => 1 } ])

    assert_nil card[:author]
    assert_equal 1, card[:leaf_count]
  end

  test "a book whose leaf count is zero still adds zero" do
    card = LibraryCard.load_legacy(
      "title" => "Quiet",
      "author" => "Grace",
      "books" => [ { "leaf_count" => 0 } ]
    )

    assert_equal 0, card[:leaf_count]
  end
end
