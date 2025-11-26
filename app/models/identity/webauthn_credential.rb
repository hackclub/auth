class Identity::WebauthnCredential < ApplicationRecord
  belongs_to :identity

  validates :external_id, presence: true, uniqueness: true
  validates :public_key, presence: true
  validates :sign_count, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :set_initial_sign_count, on: :create

  # WebAuthn credential IDs and public keys are binary data that need to be
  # base64url encoded for storage and transmission
  def webauthn_id
    Base64.urlsafe_decode64(external_id)
  end

  def webauthn_id=(value)
    self.external_id = Base64.urlsafe_encode64(value, padding: false)
  end

  def webauthn_public_key
    Base64.urlsafe_decode64(public_key)
  end

  def webauthn_public_key=(value)
    self.public_key = Base64.urlsafe_encode64(value, padding: false)
  end

  # Increment the sign count after successful authentication
  # This helps detect credential cloning attacks
  def increment_sign_count!
    increment!(:sign_count)
  end

  # Human-readable display for the credential
  def display_name
    nickname.presence || "Passkey created #{created_at.strftime('%b %d, %Y')}"
  end

  private

  def set_initial_sign_count
    self.sign_count ||= 0
  end
end
