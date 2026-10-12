class BooksController < ApplicationController
  def destroy
    book = Book.find(params[:id])
    unless Current.account&.role == "admin" || book.grants.exists?(account: Current.account, level: "editor")
      head :forbidden
      return
    end

    book.destroy!
    head :no_content
  end
end
