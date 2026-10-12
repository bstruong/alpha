class BookSearch
  def self.call(account, term)
    Book.where(id: account.visible_books.select(:id)).where("title LIKE ?", "%#{term}%")
  end
end
