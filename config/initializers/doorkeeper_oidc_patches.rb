# frozen_string_literal: true

# These patches thread the current identity session through doorkeeper-openid_connect's
# ID token generation, so auth_time reflects the actual session that authorized the
# request — not just the most recently created session for the identity.
#
# The flow:
#   1. Authorization endpoint (user in browser): Current.identity_session is set by
#      ApplicationController. The grant is stamped with source_session_id.
#   2. Token endpoint (RP server exchanging auth code): No user session cookie, but
#      we load the source session from the grant and set it directly on the IdToken.
#   3. IdToken checks @source_session (from grant) then Current.identity_session
#      (from cookie). Returns nil if neither is available — we don't guess.

Rails.application.config.to_prepare do
  # Stamp source_session_id on the grant at authorization time
  Doorkeeper::OAuth::Authorization::Code.prepend(Module.new do
    private

    def access_grant_attributes
      super.merge(source_session_id: Current.identity_session&.id)
    end
  end)

  # At code exchange, set the source session directly on the IdToken from the grant.
  # We call super first (openid_connect creates the IdToken), then attach the session.
  # Current.identity_session stays honest — it only means "the session behind this request."
  Doorkeeper::OAuth::AuthorizationCodeRequest.prepend(Module.new do
    private

    def after_successful_response
      super
      if grant.source_session_id && @response.id_token
        session = IdentitySession.find_by(id: grant.source_session_id)
        @response.id_token.instance_variable_set(:@source_session, session)
      end
    end
  end)

  # Use the real session for auth_time: @source_session (from grant, set during code
  # exchange) or Current.identity_session (from cookie, set during controller flows).
  # Returns nil if neither is available — don't guess, don't lie.
  Doorkeeper::OpenidConnect::IdToken.prepend(Module.new do
    private

    def auth_time
      session = @source_session || Current.identity_session
      return nil unless session

      [session.created_at, session.last_step_up_at].compact.max.to_i
    end
  end)
end
