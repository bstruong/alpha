require "test_helper"

class VerifierTest < ActiveSupport::TestCase
  setup do
    @subject = Account.create!(name: "Ada", email: "ada@example.com", role: "member")
    @bystander = Account.create!(name: "Grace", email: "grace@example.com", role: "member")
    @private_book = Book.create!(account: @subject, title: "Notes", author: "Ada", shared: false, page_count: 1)
    @draft = @private_book.drafts.create!(body: "secret", superseded: true)
    @search = @private_book.search_entries.create!(term: "secret")
    @shared = Book.create!(account: @subject, title: "Handbook", author: "Ada", shared: true, page_count: 4)
    @shared_draft = @shared.drafts.create!(body: "public", superseded: false)
    Grant.create!(account: @bystander, book: @shared, level: "reader")
    SignIn.create!(email: @subject.email, signed_in_at: Time.current)
    SignIn.create!(email: @bystander.email, signed_in_at: Time.current)
  end

  test "a private book is gone, including its draft and search row" do
    @subject.erase!

    assert_not Book.exists?(@private_book.id)
    assert_not Draft.exists?(@draft.id)
    assert_not SearchEntry.exists?(@search.id)
    assert_not Account.exists?(@subject.id)
  end

  test "a shared book keeps working under a deleted author" do
    @subject.erase!

    @shared.reload
    assert_equal "Deleted author", @shared.author
    assert_nil @shared.account_id
    assert_equal "public", @shared_draft.reload.body
  end

  test "a previously deactivated account is erased under the address they signed in with" do
    hidden = Account.create!(name: "Kay", email: "kay@example.com")
    SignIn.create!(email: "kay@example.com", signed_in_at: Time.current)
    hidden.update!(active: false, original_email: "kay@example.com", email: "kay-deactivated@example.com")
    private_book = Book.create!(account: hidden, title: "Kay notes", author: "Kay", shared: false, page_count: 1)

    hidden.erase!

    assert_not Account.exists?(hidden.id)
    assert_not Book.exists?(private_book.id)
    assert_not SignIn.exists?(email: "kay@example.com")
    assert_not SignIn.exists?(email: "kay-deactivated@example.com")
  end

  test "a bystander keeps their sign-in and their grant" do
    grant_id = Grant.find_by!(account: @bystander, book: @shared).id

    @subject.erase!

    assert Account.exists?(@bystander.id)
    assert SignIn.exists?(email: @bystander.email)
    assert Grant.exists?(grant_id)
  end
end
