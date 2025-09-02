class ApplicationController < ActionController::Base
  include PublicActivity::StoreController
  include IsSneaky

  helper_method :current_identity, :identity_signed_in?, :current_onboarding_step

  before_action :invalidate_v1_sessions, :authenticate_identity!, :set_honeybadger_context

  before_action :set_paper_trail_whodunnit

  def current_identity
    @current_identity ||= Identity.find_by(id: session[:identity_id]) if session[:identity_id]
  end

  alias_method :user_for_public_activity, :current_identity

  def user_for_paper_trail = current_identity&.id

  def identity_signed_in? = !!current_identity


  def invalidate_v1_sessions
    if cookies["_identity_vault_session"]
      cookies.delete("_identity_vault_session",
                     path: "/",
                     secure: Rails.env.production?,
                     httponly: true)
    end
  end

  def authenticate_identity!
    unless identity_signed_in?
      session[:oauth_return_to] = request.original_url unless request.xhr?
      # JANK ALERT
      hide_some_data_away

      # EW
      return if controller_name == "onboardings"

      redirect_to welcome_onboarding_path
    end
  end

  def set_honeybadger_context
    Honeybadger.context({
      identity_id: current_identity&.id
    })
  end

  def current_onboarding_step
    identity = current_identity

    return :basic_info unless identity&.persisted?
    return :document unless identity.verifications.where(status: [ "approved", "pending" ]).any?

    :submitted
  rescue => e
    Rails.logger.error "Error determining onboarding step: #{e.message}"
    :basic_info
  end

  rescue_from ActiveRecord::RecordNotFound do |e|
    flash[:error] = "sorry, couldn't find that object... (404)"
    redirect_to root_path
  end
end
