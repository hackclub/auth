module WebauthnAuthenticatable
  extend ActiveSupport::Concern

  private

  def generate_webauthn_authentication_options(identity, session_key:, user_verification: "preferred")
    credentials = identity.webauthn_credentials.pluck(:external_id).map { |id| Base64.urlsafe_decode64(id) }

    options = WebAuthn::Credential.options_for_get(
      allow: credentials,
      user_verification: user_verification
    )

    session[session_key] = options.challenge
    Rails.logger.info "WebAuthn options: session_key=#{session_key}, challenge=#{Base64.urlsafe_encode64(options.challenge)}"
    options
  end

  def verify_webauthn_credential(identity, credential_data:, session_key:)
    webauthn_credential = WebAuthn::Credential.from_get(credential_data)

    stored_challenge = session[session_key]
    Rails.logger.info "WebAuthn verify: session_key=#{session_key}, challenge=#{stored_challenge.present? ? Base64.urlsafe_encode64(stored_challenge) : 'nil'}"

    Identity::WebauthnCredential.transaction do
      credential = identity.webauthn_credentials.lock.find_by(
        external_id: Base64.urlsafe_encode64(webauthn_credential.id, padding: false)
      )

      return nil unless credential

      webauthn_credential.verify(
        stored_challenge,
        public_key: credential.webauthn_public_key,
        sign_count: credential.sign_count
      )

      credential.update!(sign_count: webauthn_credential.sign_count)
      credential.touch unless credential.saved_change_to_sign_count?

      session.delete(session_key)
      credential
    end
  end
end
