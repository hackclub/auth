# Drives the real login flow rather than stubbing current_session.
#
# Stubbing is fine for specs that merely need "somebody is signed in", but every
# spec in this feature is about how the cookie resolves to an account — stubbing
# the resolver would prove nothing. This exercises the actual cookie.
module AuthenticationHelpers
  # Signs an identity in through /login, returning its IdentitySession.
  # Handles the TOTP step when the identity requires two factors.
  def sign_in_as(identity, return_to: nil)
    post "/login", params: { email: identity.primary_email, return_to: return_to }.compact

    attempt = LoginAttempt.where(identity: identity).order(:created_at).last
    raise "no login attempt created for #{identity.primary_email}" if attempt.nil?

    code = Identity::V2LoginCode.active.where(identity: identity).order(:created_at).last
    raise "no login code issued for #{identity.primary_email}" if code.nil?

    post "/login/#{attempt.to_param}/verify", params: { code: code.code }

    complete_totp_step(identity, attempt) if identity.requires_two_factor?

    identity.sessions.reload.order(:created_at).last
  end

  # Signs in a second (or third) account into the same browser session, the way
  # "use another account" does.
  def add_account(identity, pending: nil)
    post add_browser_account_path(pending: pending)
    sign_in_as(identity)
  end

  # Identity#totp only returns *verified* enrolments, so an unverified TOTP would
  # leave requires_two_factor? false and silently produce a single-factor session.
  def enrol_totp(identity)
    identity.update!(use_two_factor_authentication: true)
    Identity::TOTP.create!(identity: identity).mark_verified!
    identity.reload
  end

  def current_browser_session_record
    BrowserSession.order(:created_at).last
  end

  private

  def complete_totp_step(identity, attempt)
    totp = identity.totp
    raise "#{identity.primary_email} requires two factors but has no TOTP" if totp.nil?

    post "/login/#{attempt.to_param}/totp",
      params: { code: ROTP::TOTP.new(totp.secret, issuer: Identity::TOTP::ISSUER).now }
  end
end
