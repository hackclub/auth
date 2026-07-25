# Verifies an `id_token_hint` we issued and extracts its subject.
#
# Signature and issuer are checked; expiry deliberately is not — OIDC Core
# requires that an expired ID token still be accepted as a hint, which is the
# normal case (the RP is telling us who the user was last time).
class IdTokenHintVerifier
  Result = Data.define(:subject, :error) do
    def present? = subject.present?
    def invalid? = error.present?
  end

  class << self
    def call(hint, audience: nil)
      return Result.new(subject: nil, error: nil) if hint.blank?

      payload = decode(hint)
      return Result.new(subject: nil, error: :invalid_request) if payload.nil?
      return Result.new(subject: nil, error: :invalid_request) unless issuer_matches?(payload)
      return Result.new(subject: nil, error: :invalid_request) unless audience_matches?(payload, audience)

      subject = payload["sub"].presence
      return Result.new(subject: nil, error: :invalid_request) if subject.nil?

      Result.new(subject: subject, error: nil)
    end

    private

    def decode(hint)
      key = Doorkeeper::OpenidConnect.signing_key
      return nil if key.nil?

      JWT.decode(
        hint,
        key.keypair.public_key,
        true,
        algorithm: Doorkeeper::OpenidConnect.signing_algorithm.to_s.upcase,
        verify_expiration: false,
        verify_iat: false
      ).first
    rescue JWT::DecodeError, NoMethodError
      nil
    end

    def issuer_matches?(payload)
      payload["iss"].to_s == expected_issuer
    end

    # An RP handing us another client's ID token has no business steering our
    # account selection.
    def audience_matches?(payload, audience)
      return true if audience.blank?

      Array(payload["aud"]).include?(audience.to_s)
    end

    def expected_issuer
      configured = Doorkeeper::OpenidConnect.configuration.issuer
      configured.respond_to?(:call) ? configured.call(nil, nil).to_s : configured.to_s
    end
  end
end
