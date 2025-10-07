class Identity::TOTP < ApplicationRecord
  ISSUER = "HC_IDp_#{Rails.env}"

  acts_as_paranoid

  include AASM

  aasm do
    state :unverified, initial: true
    state :verified
    state :expired

    event :mark_verified do
      transitions from: :unverified, to: :verified do
        guard do
          created_at > 15.minutes.ago
        end
      end
    end

    event :mark_expired do
      transitions from: :verified, to: :expired
    end
  end

  belongs_to :identity
  has_encrypted :secret
  validates :secret, presence: true

  include PublicActivity::Model
  tracked owner: proc{ |controller, record| record.identity }, recipient: proc { |controller, record| record.identity }, only: [:create]

  before_validation do
    self.secret ||= ROTP::Base32.random
  end

  delegate :verify, to: :instance

  def provisioning_uri
    instance.provisioning_uri(user.email)
  end

  private

  def instance
    ROTP::TOTP.new(secret, issuer: ISSUER)
  end
end
