class ApplicationController < ActionController::Base
  include PublicActivity::StoreController
  include SessionsHelper
  include StepUpAuthenticatable

  helper_method :current_identity, :identity_signed_in?, :current_onboarding_step, :current_user

  def current_user = nil # TODO: this is a temp hack to fix partials until /backend auth is replaced

  helper_method :detected_country_alpha2

  before_action :invalidate_v1_sessions, :authenticate_identity!, :set_honeybadger_context

  before_action :set_paper_trail_whodunnit
  before_action :touch_session_last_seen_at

  def user_for_public_activity = current_identity

  def user_for_paper_trail = current_identity&.id

  def info_for_paper_trail = { extra_data: { ip: request.remote_ip, user_agent: request.user_agent }.compact_blank }

  def identity_signed_in? = !!current_identity

  helper_method :directory_admin_session?

  # directory admin powers need the same session as /backend: one that passed TOTP or a
  # passkey. without it a directory admin is just a person with whatever grants they hold.
  def directory_admin_session?
    !!current_identity&.backend_user&.directory_services_admin? && two_factor_session?
  end

  def two_factor_session?
    login_attempt = current_session&.login_attempt
    !!(login_attempt&.authenticated_with_totp || login_attempt&.authenticated_with_webauthn)
  end


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
      return if controller_name == "onboardings"

      if request.xhr?
        redirect_to welcome_path
      else
        redirect_to welcome_path(return_to: request.original_url)
      end
    end
  end

  # an open manual verification call case supersedes the self-serve
  # verification flows — controllers serving those flows use this as a
  # before_action so users land on their case instead of a legacy page
  def redirect_to_open_manual_case
    return unless current_identity.verification_cases.open_cases.exists?

    redirect_to manual_verification_path
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

  # rescue_from matches the most recently declared handler first, so the
  # catch-all has to come before the specific ones or it shadows them
  rescue_from StandardError do |e|
    raise e if Rails.env.local?

    @event_id = Sentry.capture_exception(e)&.event_id
    render_error_page "errors/internal_server_error", :internal_server_error
  end

  # a stale form (session reset in another tab) is the client's problem, not a 500
  rescue_from ActionController::InvalidAuthenticityToken do
    render_error_page "errors/unprocessable_entity", :unprocessable_content
  end

  rescue_from ActiveRecord::RecordNotFound, ActionController::RoutingError do
    render_error_page "errors/not_found", :not_found
  end

  private

  # html whatever was asked for (an export.csv 404 has no csv template to render)
  def render_error_page(template, status)
    render template, layout: "errors", status: status, formats: [ :html ], content_type: "text/html"
  end

  def touch_session_last_seen_at = current_session&.touch_last_seen_at
end
