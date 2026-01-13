module WebauthnAuthenticatable
  extend ActiveSupport::Concern

  private

  def generate_webauthn_authentication_options(identity, session_key:, user_verification: "required")
    credentials = identity.webauthn_credentials.active.pluck(:external_id).map { |id| Base64.urlsafe_decode64(id) }

    options = WebAuthn::Credential.options_for_get(
      allow: credentials,
      user_verification: user_verification
    )

    session[session_key] = options.challenge
    Rails.logger.info "WebAuthn options generated: session_key=#{session_key}"
    options
  end

  def verify_webauthn_credential(identity, credential_data:, session_key:)
    webauthn_credential = WebAuthn::Credential.from_get(credential_data)

    # Delete challenge immediately to prevent replay attacks (single-use)
    stored_challenge = session.delete(session_key)
    Rails.logger.info "WebAuthn verify: session_key=#{session_key}, challenge_present=#{stored_challenge.present?}"

    return nil unless stored_challenge.present?

    Identity::WebauthnCredential.transaction do
      credential = identity.webauthn_credentials.active.lock.find_by(
        external_id: Base64.urlsafe_encode64(webauthn_credential.id, padding: false)
      )

      return nil unless credential

      begin
        webauthn_credential.verify(
          stored_challenge,
          public_key: credential.webauthn_public_key,
          sign_count: credential.sign_count
        )

        credential.update!(sign_count: webauthn_credential.sign_count)
        credential.touch unless credential.saved_change_to_sign_count?

        credential
      rescue WebAuthn::SignCountVerificationError => e
        Rails.logger.warn "WebAuthn sign count anomaly detected: credential_id=#{credential.id}, identity_id=#{identity.id}"
        credential.mark_as_compromised!
        raise WebauthnCredentialCompromisedError.new(credential)
      end
    end
  end
end

class WebauthnCredentialCompromisedError < StandardError
  attr_reader :credential

  def initialize(credential)
    @credential = credential
    super("Passkey may be compromised due to sign count anomaly")
  end
end
