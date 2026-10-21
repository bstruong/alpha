In `app/controllers/books_controller.rb`, enforce authorization on book deletion.
Only an editor of a book (with a grant level of 'editor'), or an administrator, may delete that book.
Unauthorized deletion attempts must return HTTP 403 Forbidden (`head :forbidden`).
Ensure `bin/rails test` passes.
