class LoginAttempt < ApplicationRecord
  include AASM
  include Hashid::Rails

  belongs_to :identity
  belongs_to :session, optional: true, class_name: "IdentitySession"

  has_encrypted :browser_token
  before_validation :ensure_browser_token

  store_accessor :authentication_factors, :email, :totp, :backup_code, :webauthn, :legacy_email, prefix: :authenticated_with

  EXPIRATION = 15.minutes

  scope :active, -> { where(created_at: EXPIRATION.ago..) }

  has_paper_trail skip: [ :browser_token ]

  validate do
    if session.present? && !complete?
      # how did we create session when it's not complete?!
      Rails.error.unexpected "An incomplete login #{id} has a session #{session.id} present."
      errors.add(:base, "An incomplete login has a session present.")
    end
  end

  validate do
    if session.present? && session.identity != identity
      Rails.error.unexpected "A login with a session present has a session.identity (#{session.identity.id}) / identity (#{identity.id}) mismatch."
      errors.add(:base, "A login with a session present has a session.identity / identity mismatch.")
    end
  end

  aasm do
    state :incomplete, initial: true
    state :complete

    event :mark_complete do
      transitions from: :incomplete, to: :complete do
        guard do
          authentication_factors_count == required_authentication_factors_count
        end
      end
    end
  end

  before_save do
    mark_complete! if may_mark_complete?
  end

  def authentication_factors_count
    return 0 if authentication_factors.nil?

    authentication_factors.values.count(true)
  end

  def ensure_browser_token
    # Avoid generating a new token if one is already encrypted
    return if self[:browser_token_ciphertext].present?

    self.browser_token ||= SecureRandom.base58(24)
  end

  def email_available?
    # If legacy_email factor is already satisfied (migration flow), email code is not available/needed
    !authenticated_with_email && !authenticated_with_legacy_email
  end



  def totp_available? = !authenticated_with_totp && identity.totp.present?

  def backup_code_available? = !authenticated_with_backup_code && identity.backup_codes_enabled?

  def webauthn_available? = !authenticated_with_webauthn && identity.webauthn_enabled?

  def available_factors
    factors = []
    factors << :email if email_available?
    factors << :webauthn if webauthn_available?
    factors << :totp if totp_available?
    factors << :backup_code if backup_code_available?
    factors
  end

  private

  def required_authentication_factors_count
    # WebAuthn inherently provides 2FA (possession + biometric/PIN)
    # So if WebAuthn is used, we only need 1 factor
    if authenticated_with_webauthn
      1
    # Require 2FA if enabled AND at least one 2FA method is configured
    elsif identity.requires_two_factor?
      2
    else
      1
    end
  end
end
