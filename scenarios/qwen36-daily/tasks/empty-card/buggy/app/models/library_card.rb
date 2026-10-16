class LibraryCard
  def self.load_legacy(payload)
    books = payload.fetch("books")
    {
      title: payload.fetch("title"),
      author: payload.fetch("author"),
      leaf_count: books.sum { |book| book.fetch("leaf_count") }
    }
  end
end
