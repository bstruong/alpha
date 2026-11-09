Open `app/models/book_search.rb`.

Replace the raw LIKE interpolation with:
`pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term.to_s)}%"`

Do not change other files. Leave `bin/rails test` green.
