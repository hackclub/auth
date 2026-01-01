class ApplicationController < ActionController::Base
  include PublicActivity::StoreController
  include IsSneaky
  include SessionsHelper
  include StepUpAuthenticatable

  helper_method :current_identity, :identity_signed_in?, :current_onboarding_step, :current_user

  def current_user = nil # TODO: this is a temp hack to fix partials until /backend auth is replaced

  helper_method :detected_country_alpha2

  before_action :invalidate_v1_sessions, :authenticate_identity!, :set_honeybadger_context

  before_action :set_paper_trail_whodunnit
  before_action :touch_session_last_seen_at

  alias_method :user_for_public_activity, :current_identity

  def user_for_paper_trail = current_identity&.id

  def info_for_paper_trail = { extra_data: { ip: request.remote_ip, user_agent: request.user_agent }.compact_blank }

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
      # JANK ALERT
      hide_some_data_away

      # EW
      return if controller_name == "onboardings"

      if request.xhr?
        redirect_to welcome_path
      else
        redirect_to welcome_path(return_to: request.original_url)
      end
    end
  end

  def set_honeybadger_context
    return unless current_identity

    Sentry.set_user(
      id: current_identity.public_id,  # Use public_id (ident!xyz) not database ID
      email: current_identity.primary_email
    )

    Sentry.set_context(:identity, {
      identity_public_id: current_identity.public_id,
      identity_email: current_identity.primary_email,
      slack_id: current_identity.slack_id
    }.compact)
  end

  # Best-effort country detection from request IP; returns ISO3166 alpha-2.
  # Falls back to "US" if detection fails or result is not in our enum.
  def detected_country_alpha2
    ip = request.remote_ip
    return nil if ip.blank?

    begin
      result = Geocoder.search(ip).first
      code = result&.country_code&.upcase
      # Ensure the code maps to a known enum key
      if code.present? && Identity.send(:country_enum_list).key?(code.to_sym)
        code
      else
        "US"
      end
    rescue => e
      Rails.logger.info("geoip failed: #{e.class}: #{e.message}")
      "US"
    end
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
    event_id = Sentry.capture_exception(e)
    flash[:error] = "sorry, couldn't find that object... (404)"
    flash[:sentry_event_id] = event_id if event_id
    redirect_to root_path unless request.path == "/"
  end

  rescue_from StandardError do |e|
    event_id = Sentry.capture_exception(e)
    flash[:error] = "Something went wrong. Please try again."
    flash[:sentry_event_id] = event_id if event_id

    raise e if Rails.env.development?
    redirect_to root_path unless request.path == "/"
  end

  private

  def touch_session_last_seen_at
    current_session&.touch_last_seen_at
  end
end
