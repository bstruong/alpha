class AccountsController < ApplicationController
  def update
    account = Account.find(params[:id])
    account.update!(account_params)
    render json: { id: account.id, name: account.name, email: account.email, role: account.role }
  end

  private
    def account_params
      params.require(:account).permit(:name, :email, :role)
    end
end
