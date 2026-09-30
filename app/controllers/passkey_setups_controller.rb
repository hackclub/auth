class PasskeySetupsController < ApplicationController
  include SafeUrlValidation

  layout "logged_out"

  before_action :redirect_unless_eligible, only: :show

  def show
    @return_to = url_from(params[:return_to])
  end

  def skip
    session[:passkey_promotion_dismissed] = true
    current_identity.dismiss_passkey_promotion! if params[:dont_show_again] == "true"
    redirect_to destination
  end

  private

  def redirect_unless_eligible
    redirect_to destination unless show_passkey_promotion?
  end

  def destination
    url_from(params[:return_to]) || root_path
  end
end
