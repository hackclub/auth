class Identity::TOTP < ApplicationRecord
  ISSUER = "HC_IDp_#{Rails.env}"

  include TwoFactorAuthenticatable

  has_encrypted :secret
  validates :secret, presence: true

  include PublicActivity::Model
  tracked owner: proc { |controller, record| record.identity }, recipient: proc { |controller, record| record.identity }, only: [ :create ]

  before_validation do
    self.secret ||= ROTP::Base32.random
  end

  def verify_code(code, drift_behind: 30, drift_ahead: 30)
    instance.verify(code, drift_behind: drift_behind, drift_ahead: drift_ahead)
  end

  def verify(code, **options)
    verify_code(code, **options)
  end

  def provisioning_uri
    instance.provisioning_uri(identity.primary_email)
  end

  def method_name
    "Authenticator App (TOTP)"
  end

  def method_icon
    "message"
  end

  private

  def instance
    ROTP::TOTP.new(secret, issuer: ISSUER)
  end
end
