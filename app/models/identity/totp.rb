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
    with_lock do
      ts = instance.verify(code, drift_behind: drift_behind, drift_ahead: drift_ahead, after: last_used_at&.to_i)
      update_column(:last_used_at, Time.at(ts)) if ts
      ts
    end
  end

  def verify(code, **options)
    verify_code(code, **options)
  end

  def provisioning_uri = instance.provisioning_uri(identity.primary_email)

  def method_name = "Authenticator App (TOTP)"

  def method_icon = "message"

  private

  def instance = ROTP::TOTP.new(secret, issuer: ISSUER)
end
