class AccountsController < ApplicationController
  def update
    account = Account.find(params[:id])
    account.update!(account_params)
    render json: { id: account.id, name: account.name, email: account.email, role: account.role }
  end

  private
    def account_params
      keys = [ :name, :email ]
      keys << :role if Current.account&.role == "admin"
      params.require(:account).permit(*keys)
    end
end
