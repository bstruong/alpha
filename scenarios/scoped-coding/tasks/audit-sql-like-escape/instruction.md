In `app/models/book_search.rb`, sanitize search terms so special characters like `%` and `_` are treated as literal text and not wildcards.
Use `ActiveRecord::Base.sanitize_sql_like(term.to_s)`.
Ensure `bin/rails test` passes.
