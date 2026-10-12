require "test_helper"

class LibraryCardTest < ActiveSupport::TestCase
  test "a card with books keeps its title author and leaf count" do
    card = LibraryCard.load_legacy(
      "title" => "Shelf",
      "author" => "Ada",
      "books" => [ { "leaf_count" => 2 }, { "leaf_count" => 3 } ]
    )

    assert_equal({ title: "Shelf", author: "Ada", leaf_count: 5 }, card)
  end
end
