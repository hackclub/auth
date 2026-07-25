class SessionsController < ApplicationController
  # Signing out with several accounts in the browser leaves the browser session
  # alive but with no active account, so this has to stay reachable.
  skip_before_action :authenticate_identity!, only: [ :logout_all ]

  def logout
    # Read the flag before signing out — afterwards there's no identity to gate on.
    per_account = Flipper.enabled?(BrowserAccountsController::FEATURE_FLAG, current_identity)

    result = per_account ? sign_out : sign_out_all_accounts

    if result == :accounts_remaining
      flash[:info] = "Signed out of that account."
      redirect_to browser_accounts_path
    else
      flash[:info] = "You've been logged out. Nice seeing you!"
      redirect_to welcome_path
    end
  end

  def logout_all
    sign_out_all_accounts

    flash[:info] = "You've been signed out of every account in this browser."
    redirect_to welcome_path
  end
end
