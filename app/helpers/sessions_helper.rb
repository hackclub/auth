# frozen_string_literal: true

module SessionsHelper
  class AccountLockedError < StandardError; end
  class AccountLimitError < StandardError; end

  SESSION_DURATION = 1.month
  COOKIE_NAME = :session_token

  # Signs `identity` in. By default the account joins whatever browser session
  # this request already has, so a browser can hold several accounts at once.
  # Pass `browser_session: nil` to deliberately start a fresh one.
  #
  # Signing in account B never inherits account A's authentication — B gets its
  # own IdentitySession, with its own expiry, step-up state and login factors.
  def sign_in(identity:, fingerprint_info: {}, browser_session: :current)
    raise(AccountLockedError, "Your HCB account has been locked.") if identity.locked?

    # Preserve fingerprint info from session if not passed
    fingerprint_info = session[:fingerprint_info] if fingerprint_info.blank? && session[:fingerprint_info].present?
    fingerprint_info = (fingerprint_info || {}).with_indifferent_access

    # Preserve flow data before resetting session
    return_to = session[:return_to]

    target = browser_session == :current ? current_browser_session : browser_session

    reset_session

    # Restore flow data after session reset
    session[:return_to] = return_to if return_to.present?

    expires_at = SESSION_DURATION.from_now
    session_attributes = {
      session_token: BrowserSession.generate_token,
      fingerprint: fingerprint_info[:fingerprint],
      device_info: fingerprint_info[:device_info],
      os_info: fingerprint_info[:os_info],
      timezone: fingerprint_info[:timezone],
      ip: fingerprint_info[:ip],
      expires_at: expires_at
    }

    ident_session = nil
    added_to_existing = false

    BrowserSession.transaction do
      if target&.persisted? && !target.expired?
        existing = target.identity_session_for(identity)

        if existing
          # This was a real authentication, not an account switch. Replace the
          # old session so expiry, auth_time and the LoginAttempt assurance
          # binding all describe the authentication that just completed.
          existing.revoke!(reason: "reauthenticated")
          ident_session = identity.sessions.create!(browser_session: target, **session_attributes)
        else
          raise AccountLimitError if target.at_account_limit?

          added_to_existing = target.live_identity_sessions.exists?
          ident_session = identity.sessions.create!(browser_session: target, **session_attributes)
        end

        target.activate!(ident_session)
        # Rotate on every change to the account set (session fixation).
        target.rotate_token!
        target.extend_expiry!(expires_at)
      else
        target = BrowserSession.start!(expires_at: expires_at)
        ident_session = identity.sessions.create!(browser_session: target, **session_attributes)
        target.activate!(ident_session)
      end
    end

    write_browser_session_cookie(target)

    if added_to_existing
      # Deliberately does not name the other accounts in this browser: audit log
      # entries are visible to the account they belong to.
      ident_session.create_activity :account_added, owner: identity, recipient: identity
    end

    @current_browser_session = target
    @current_session = ident_session
    self.current_identity = identity

    ident_session
  end

  # Makes an account that's already signed into this browser the active one.
  def switch_account!(identity_session)
    browser_session = current_browser_session
    return nil if browser_session.nil?
    return nil unless identity_session&.live?
    return nil unless identity_session.browser_session_id == browser_session.id

    browser_session.activate!(identity_session)
    browser_session.rotate_token!
    write_browser_session_cookie(browser_session)

    identity_session.create_activity :account_switched,
      owner: identity_session.identity, recipient: identity_session.identity

    @current_session = identity_session
    self.current_identity = identity_session.identity

    identity_session
  end

  # Set while a signed-in user is deliberately authenticating an additional
  # account, which is the one case where reaching the login form while already
  # signed in is intended.
  def adding_account? = session[:adding_account].present?

  def ensure_no_user!
    return if adding_account?

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

  def current_browser_session
    return @current_browser_session if defined?(@current_browser_session)

    token = cookies.encrypted[COOKIE_NAME]
    return @current_browser_session = nil if token.blank?

    resolution = SessionResolver.resolve(token)

    @current_browser_session =
      if resolution.nil?
        nil
      elsif resolution.legacy?
        SessionResolver.adopt_legacy!(resolution.identity_session, token: token)
      else
        resolution.browser_session
      end
  end

  # The account session this request is acting as. Nil when the active account
  # has expired even though siblings are still live — we never silently promote
  # another account, because that would change `sub` mid-session.
  def current_session
    return @current_session if defined?(@current_session)

    @current_session = current_browser_session&.active_session
  end

  # The account a relying-party request is being authorized for. Set by
  # OidcAccountSelection when the browser holds several accounts; otherwise the
  # active one. Defined here rather than as a controller helper_method so views
  # rendered outside that concern degrade sensibly instead of raising.
  def authorizing_identity
    @oidc_selected_identity || current_identity
  end

  def account_chooser_available?
    Flipper.enabled?(BrowserAccountsController::FEATURE_FLAG, current_identity)
  end

  def other_account_sessions
    browser_session = current_browser_session
    return IdentitySession.none if browser_session.nil?

    browser_session.live_identity_sessions.where.not(id: current_session&.id)
  end

  def multiple_accounts_signed_in?
    (current_browser_session&.account_count || 0) > 1
  end

  # Signs out one account, not the browser. Returns :accounts_remaining when
  # other accounts are still signed in here, otherwise :signed_out.
  def sign_out(identity_session: current_session, reason: "user_signout")
    browser_session = current_browser_session
    target = identity_session

    if target
      target.revoke!(reason: reason)
      target.create_activity :sign_out, owner: target.identity, recipient: target.identity
    end

    if browser_session
      browser_session.reload

      if browser_session.live_identity_sessions.exists?
        if browser_session.active_identity_session_id == target&.id
          browser_session.update!(active_identity_session: nil)
        end
        browser_session.rotate_token!
        write_browser_session_cookie(browser_session)

        @current_browser_session = browser_session
        @current_session = nil
        self.current_identity = nil

        return :accounts_remaining
      end

      browser_session.destroy!
    end

    forget_browser_session_cookie
    @current_browser_session = nil
    @current_session = nil
    self.current_identity = nil

    reset_session

    :signed_out
  end

  # Signs out every account in this browser and discards the browser session.
  def sign_out_all_accounts(reason: "user_signout_all")
    browser_session = current_browser_session

    if browser_session
      browser_session.live_identity_sessions.each do |ident_session|
        ident_session.revoke!(reason: reason)
        ident_session.create_activity :sign_out,
          owner: ident_session.identity, recipient: ident_session.identity
      end
      browser_session.destroy!
    end

    forget_browser_session_cookie
    @current_browser_session = nil
    @current_session = nil
    self.current_identity = nil

    reset_session

    :signed_out
  end

  # Removes an account from this browser without touching the active one.
  def remove_account!(identity_session, reason: "user_removed")
    browser_session = current_browser_session
    return nil if browser_session.nil?
    return nil unless identity_session&.browser_session_id == browser_session.id

    return sign_out(identity_session: identity_session, reason: reason) if identity_session.id == current_session&.id

    identity_session.revoke!(reason: reason)
    identity_session.create_activity :account_removed,
      owner: identity_session.identity, recipient: identity_session.identity

    browser_session.rotate_token!
    write_browser_session_cookie(browser_session)

    :removed
  end

  # Every session for this identity on other devices. Distinct from the accounts
  # held by this browser — don't conflate the two in UI.
  def sign_out_of_all_sessions(identity = current_identity)
    # Destroy all the sessions except the current session
    identity
      &.sessions
      &.where&.not(id: current_session&.id)
      &.update_all(signed_out_at: Time.now, expires_at: Time.now, revoked_reason: "user_signout_other_devices")
  end

  private

  def write_browser_session_cookie(browser_session)
    cookies.encrypted[COOKIE_NAME] = {
      value: browser_session.token,
      expires: browser_session.expires_at,
      httponly: true,
      secure: Rails.env.production?,
      same_site: :lax
    }
  end

  def forget_browser_session_cookie
    cookies.delete(COOKIE_NAME)
    # Written by an earlier implementation, never read, and previously never
    # cleaned up on sign-out.
    cookies.delete(:signed_user)
  end
end
