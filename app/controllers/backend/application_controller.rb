module Backend
  class ApplicationController < ActionController::Base
    include PublicActivity::StoreController
    include Pundit::Authorization
    include ::SessionsHelper
    include Hints::Controller
    include Hints::Shortcuts

    layout "backend"

    after_action :verify_authorized

    helper_method :current_user, :user_signed_in?

    before_action :authenticate_user!, :set_honeybadger_context
    before_action :require_2fa!

    before_action :set_paper_trail_whodunnit

    def current_user
      @current_user ||= current_identity&.backend_user
    end

    def current_impersonator
      @current_impersonator ||= Identity.find_by(id: session[:impersonator_user_id])&.backend_user if session[:impersonator_user_id]
    end

    alias_method :find_current_auditor, :current_user
    alias_method :user_for_public_activity, :current_user

    def user_for_paper_trail = current_impersonator&.id || current_user&.id
    def info_for_paper_trail = { extra_data: { ip: request.remote_ip, user_agent: request.user_agent, impersonating: !!current_impersonator, pretending_to_be: current_impersonator && current_user }.compact_blank }

    def user_signed_in? = !!current_user

    def authenticate_user!
      unless current_identity
        session[:return_to] = request.original_url
        return redirect_to root_path, alert: "Please log in to access the backend."
      end

      unless current_user&.active?
        redirect_to root_path, alert: "You do not have access to the backend."
      end
    end

    def require_2fa!
      login_attempt = current_session&.login_attempt
      unless login_attempt&.authenticated_with_totp || login_attempt&.authenticated_with_webauthn
        redirect_to root_path, alert: "You must authenticate with TOTP or passkey to access the backend."
      end
    end

    def set_honeybadger_context
      return unless current_identity

      # Set user context with public_id
      Sentry.set_user(
        id: current_identity.public_id,  # Use identity public_id (ident!xyz)
        username: current_user&.username,
        email: current_identity.primary_email
      )

      # Set backend user context
      Sentry.set_context(:user, {
        user_username: current_user&.username,
        user_identity_public_id: current_user&.identity&.public_id,
        user_slack_id: current_user&.slack_id,
        is_super_admin: current_user&.super_admin?,
        is_program_manager: current_user&.program_manager?,
        can_break_glass: current_user&.can_break_glass?
      }.compact)

      # Set identity context (the identity being acted upon)
      Sentry.set_context(:identity, {
        identity_public_id: current_identity.public_id,
        identity_email: current_identity.primary_email,
        slack_id: current_identity.slack_id
      }.compact)

      # Set impersonation context if applicable
      if current_impersonator
        Sentry.set_context(:impersonation, {
          impersonator_username: current_impersonator.username,
          impersonator_identity_public_id: current_impersonator.identity&.public_id,
          is_impersonating: true
        }.compact)
      end
    end

    rescue_from Pundit::NotAuthorizedError do |e|
      event_id = Sentry.capture_exception(e)
      flash[:error] = "you don't seem to be authorized to do that?"
      flash[:sentry_event_id] = event_id if event_id
      redirect_to backend_root_path unless request.path == "/backend" || request.path == "/backend/"
    end

    rescue_from ActiveRecord::RecordNotFound do |e|
      event_id = Sentry.capture_exception(e)
      flash[:error] = "sorry, couldn't find that object... (404)"
      flash[:sentry_event_id] = event_id if event_id
      redirect_to backend_root_path unless request.path == "/backend" || request.path == "/backend/"
    end
  end
end
