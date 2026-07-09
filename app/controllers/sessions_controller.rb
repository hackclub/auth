class SessionsController < ApplicationController
  skip_before_action :require_two_factor_enrollment!

  def logout
    flash[:info] = "You've been logged out. Nice seeing you!"
    sign_out
    redirect_to welcome_path
  end
end
