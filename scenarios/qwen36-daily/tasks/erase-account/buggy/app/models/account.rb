class Account < ApplicationRecord
  has_many :books, dependent: :nullify
  has_many :grants, dependent: :destroy
  has_many :receipts, dependent: :destroy

  def library_digest
    Rails.cache.fetch("library-digest/#{id}", expires_in: 1.hour) do
      visible_books.map { |book| { id: book.id, title: book.title, leaf_count: book.leaf_count } }
    end
  end

  def visible_books
    granted_ids = grants.pluck(:book_id)
    scope = Book.where(shared: true).or(Book.where(account_id: id))
    scope = scope.or(Book.where(id: granted_ids)) if granted_ids.any?
    scope.distinct.order(:id)
  end

  def erase!
    update!(
      active: false,
      original_email: original_email || email,
      email: "deactivated-#{id}@example.com"
    )
  end
end
