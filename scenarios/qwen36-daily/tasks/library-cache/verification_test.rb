require "test_helper"

class VerifierTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @ada = Account.create!(name: "Ada", email: "ada-cache@example.com")
    @grace = Account.create!(name: "Grace", email: "grace-cache@example.com")
    @handbook = Book.create!(account: @ada, title: "Handbook", author: "Ada", shared: true, page_count: 4)
    @notes = Book.create!(account: @ada, title: "Notes", author: "Ada", shared: false, page_count: 1)
  end

  test "a digest computed second never lists a book that account cannot read" do
    @ada.library_digest

    digest = @grace.library_digest

    assert_equal [ @handbook.id ], digest.map { |entry| entry[:id] }
  end

  test "a repeated call does not query again" do
    @grace.library_digest

    assert_no_queries { @grace.library_digest }
  end

  test "a grant shows up after the hour" do
    assert_equal [ @handbook.id ], @grace.library_digest.map { |entry| entry[:id] }
    Grant.create!(account: @grace, book: @notes, level: "reader")

    travel 61.minutes
    digest = @grace.library_digest

    assert_equal [ @handbook.id, @notes.id ].sort, digest.map { |entry| entry[:id] }.sort
  end
end
