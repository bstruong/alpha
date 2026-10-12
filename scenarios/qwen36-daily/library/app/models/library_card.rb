class LibraryCard
  def self.load_legacy(payload)
    books = payload["books"] || []
    {
      title: payload["title"],
      author: payload["author"],
      leaf_count: books.sum { |book| book["leaf_count"].to_i }
    }
  end
end
