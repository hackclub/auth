# frozen_string_literal: true

# These patches thread the current identity session through doorkeeper-openid_connect's
# ID token generation, so auth_time, amr and acr reflect the actual session that
# authorized the request — not just the most recently created session for the identity.
#
# The flow:
#   1. Authorization endpoint (user in browser): Current.identity_session is set by
#      ApplicationController. The grant is stamped with source_session_id.
#   2. Token endpoint (RP server exchanging auth code): No user session cookie, but
#      we load the source session from the grant and set it directly on the IdToken.
#   3. IdToken checks @source_session (from grant) then Current.identity_session
#      (from cookie). Returns nil if neither is available — we don't guess.
#
# Once a browser can hold several accounts, "the session behind this request" is the
# selected account's session, so assurance claims can never leak across accounts.

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

  # auth_time, amr and acr all come from one session so they can never disagree.
  # nil values are dropped by IdToken#as_json, so an unknown assurance level is
  # simply absent rather than guessed.
  Doorkeeper::OpenidConnect::IdToken.prepend(Module.new do
    def claims
      super.merge(amr: amr, acr: acr)
    end

    private

    # @source_session comes from the grant during code exchange;
    # Current.identity_session from the cookie during controller flows.
    def oidc_identity_session
      @source_session || Current.identity_session
    end

    def auth_time
      session = oidc_identity_session
      return nil unless session

      [ session.created_at, session.last_step_up_at ].compact.max.to_i
    end

    def amr = oidc_identity_session&.amr_values

    def acr = oidc_identity_session&.acr_value
  end)

  # The gem's discovery document doesn't advertise prompt or acr support.
  Doorkeeper::OpenidConnect::DiscoveryController.prepend(Module.new do
    private

    def provider_response
      response = super

      response.merge(
        prompt_values_supported: %w[none login consent select_account],
        acr_values_supported: [
          IdentitySession::ACR_SINGLE_FACTOR,
          IdentitySession::ACR_MULTI_FACTOR
        ],
        claims_supported: (response[:claims_supported] || []) | %w[auth_time amr acr]
      )
    end
  end)
end
