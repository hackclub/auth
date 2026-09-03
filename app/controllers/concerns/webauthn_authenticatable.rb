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

  # Verify a discoverable passkey without a prior identity (passkey-first sign in).
  def find_and_verify_discoverable_webauthn_credential(credential_data, session_key:)
    webauthn_credential = WebAuthn::Credential.from_get(credential_data)

    credential = Identity::WebauthnCredential.active.find_by(
      external_id: Base64.urlsafe_encode64(webauthn_credential.id, padding: false)
    )

    return nil unless credential

    verify_webauthn_credential(credential.identity, credential_data:, session_key:)
  end

  def verify_webauthn_credential(identity, credential_data:, session_key:)
    # Delete challenge before parsing to prevent reuse on parse failure
    stored_challenge = session.delete(session_key)
    Rails.logger.info "WebAuthn verify: session_key=#{session_key}, challenge_present=#{stored_challenge.present?}"

    return nil unless stored_challenge.present?

    webauthn_credential = WebAuthn::Credential.from_get(credential_data)

    compromised_credential = nil

    result = Identity::WebauthnCredential.transaction do
      credential = identity.webauthn_credentials.active.lock.find_by(
        external_id: Base64.urlsafe_encode64(webauthn_credential.id, padding: false)
      )

      next nil unless credential

      begin
        webauthn_credential.verify(
          stored_challenge,
          public_key: credential.webauthn_public_key,
          sign_count: credential.sign_count,
          user_verification: true
        )

        credential.update!(sign_count: webauthn_credential.sign_count)
        credential.touch unless credential.saved_change_to_sign_count?

        credential
      rescue WebAuthn::SignCountVerificationError => e
        Rails.logger.warn "WebAuthn sign count anomaly detected: credential_id=#{credential.id}, identity_id=#{identity.id}"
        credential.update_columns(compromised_at: Time.current)
        compromised_credential = credential
        nil
      end
    end

    if compromised_credential
      Rails.logger.warn "WebAuthn credential marked as compromised: id=#{compromised_credential.id}, identity_id=#{compromised_credential.identity_id}"
      raise WebauthnCredentialCompromisedError.new(compromised_credential)
    end

    result
  end
end

class WebauthnCredentialCompromisedError < StandardError
  attr_reader :credential

  def initialize(credential)
    @credential = credential
    super("Passkey may be compromised due to sign count anomaly")
  end
end
