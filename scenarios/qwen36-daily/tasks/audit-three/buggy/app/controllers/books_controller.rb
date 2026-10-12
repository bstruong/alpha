class BooksController < ApplicationController
  def destroy
    book = Book.find(params[:id])
    book.destroy!
    head :no_content
  end
end
