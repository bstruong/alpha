require "test_helper"

class BookSearchTest < ActiveSupport::TestCase
  test "a plain word finds a title the account can read" do
    account = Account.create!(name: "Ada", email: "ada-search@example.com")
    Book.create!(account: account, title: "Handbook", author: "Ada", shared: true, page_count: 1)

    titles = BookSearch.call(account, "Hand").pluck(:title)

    assert_equal [ "Handbook" ], titles
  end
end
