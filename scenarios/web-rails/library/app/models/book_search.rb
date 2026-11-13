class BookSearch
  def self.call(account, term)
    escaped = ActiveRecord::Base.sanitize_sql_like(term.to_s)
    Book.where(id: account.visible_books.select(:id)).where("title LIKE ? ESCAPE '\\'", "%#{escaped}%")
  end
end
