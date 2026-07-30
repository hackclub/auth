# Turns the value of the session cookie into a browser session and the account
# session it currently points at.
#
# Shared by SessionsHelper and the SuperAdminConstraint in routes.rb so there is
# exactly one definition of "who is this cookie". `resolve` never writes;
# adopting a legacy session into a BrowserSession is a separate, explicit step.
class SessionResolver
  Resolution = Data.define(:browser_session, :identity_session, :legacy) do
    def legacy? = legacy
  end

  class << self
    def resolve(token)
      return nil if token.blank?

      browser_session = BrowserSession.not_expired.find_by(token: token)
      if browser_session
        return Resolution.new(
          browser_session: browser_session,
          identity_session: browser_session.active_session,
          legacy: false
        )
      end

      legacy_session = legacy_identity_session(token)
      return nil if legacy_session.nil?

      Resolution.new(browser_session: nil, identity_session: legacy_session, legacy: true)
    end

    # Read-only convenience for callers that only want the account (e.g. routing
    # constraints, which must not write).
    def identity_session(token) = resolve(token)&.identity_session

    # Cookies minted before browser sessions existed hold an IdentitySession
    # token directly. They keep working, and are adopted on next request.
    def legacy_identity_session(token)
      IdentitySession
        .not_expired
        .where(browser_session_id: nil, signed_out_at: nil)
        .find_by(session_token: token)
    end

    # Adopts a legacy session, reusing the cookie value as the browser session
    # token so nobody is logged out and no Set-Cookie is needed.
    def adopt_legacy!(identity_session, token:)
      BrowserSession.transaction do
        browser_session = BrowserSession.create!(
          token: token,
          expires_at: identity_session.expires_at || SessionsHelper::SESSION_DURATION.from_now
        )
        identity_session.update!(browser_session: browser_session)
        browser_session.activate!(identity_session)
        browser_session
      end
    rescue ActiveRecord::RecordNotUnique
      # A concurrent request in another tab adopted it first. Theirs is fine.
      BrowserSession.not_expired.find_by(token: token)
    end
  end
end
