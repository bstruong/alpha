class ApplicationController < ActionController::Base
  before_action :set_current_account

  private
    def set_current_account
      Current.account = Account.find_by(id: request.headers["X-Account-Id"])
    end
end
