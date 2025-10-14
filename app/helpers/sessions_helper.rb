# frozen_string_literal: true

module SessionsHelper
  class AccountLockedError < StandardError; end

  def sign_in(identity:, fingerprint_info: {}, impersonate: false)
    raise(AccountLockedError, "Your HCB account has been locked.") if identity.locked?

    # Preserve fingerprint info from session if not passed
    fingerprint_info = session[:fingerprint_info] if fingerprint_info.blank? && session[:fingerprint_info].present?

    # Preserve OAuth flow data before resetting session
    oauth_return_to = session[:oauth_return_to]
    stashed_data = session[:stashed_data]

    reset_session

    # Restore OAuth flow data after session reset
    session[:oauth_return_to] = oauth_return_to if oauth_return_to.present?
    session[:stashed_data] = stashed_data if stashed_data.present?

    session_token = SecureRandom.urlsafe_base64
    session_duration = 1.month
    expires_at = session_duration.seconds.from_now
    cookies.encrypted[:session_token] = {
      value: session_token,
      expires: expires_at,
      httponly: true,
      secure: Rails.env.production?,
      same_site: :lax
    }
    cookies.encrypted[:signed_user] = {
      value: identity.signed_id(expires_in: 2.months, purpose: :remember_me),
      expires: 2.months.from_now,
      httponly: true,
      secure: Rails.env.production?,
      same_site: :lax
    }
    ident_session = identity.sessions.build(
      session_token:,
      fingerprint: fingerprint_info[:fingerprint],
      device_info: fingerprint_info[:device_info],
      os_info: fingerprint_info[:os_info],
      timezone: fingerprint_info[:timezone],
      ip: fingerprint_info[:ip],
      expires_at:
    )

    ident_session.save!
    self.current_identity = identity

    ident_session
  end

  def ensure_no_user!
    if identity_signed_in?
      flash[:info] = "you're already logged in, silly!"
      redirect_to root_path
    end
  end

  def signed_in? = !current_identity.nil?

  def current_identity=(identity)
    @current_identity = identity
  end

  def current_identity
    @current_identity ||= current_session&.identity
  end

  def current_session
    return @current_session if defined?(@current_session)

    session_token = cookies.encrypted[:session_token]

    return nil if session_token.nil?

    # Find a valid session (not expired) using the session token
    @current_session = IdentitySession.not_expired.find_by(session_token:)
  end

  def sign_out
    current_identity
      &.sessions
      &.find_by(session_token: cookies.encrypted[:session_token])
      &.update(signed_out_at: Time.now, expires_at: Time.now)

    cookies.delete(:session_token)
    self.current_identity = nil

    reset_session
  end

  def sign_out_of_all_sessions(identity = current_identity)
    # Destroy all the sessions except the current session
    identity
      &.sessions
      &.where&.not(id: current_session&.id)
      &.update_all(signed_out_at: Time.now, expires_at: Time.now)
  end
end
