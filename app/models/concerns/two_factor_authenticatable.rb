# Concern for 2FA methods (TOTP, SMS, etc.)
# Include this in any model that represents a 2FA method
module TwoFactorAuthenticatable
  extend ActiveSupport::Concern

  included do
    belongs_to :identity
    acts_as_paranoid

    include AASM

    aasm do
      state :unverified, initial: true
      state :verified
      state :expired

      event :mark_verified do
        transitions from: :unverified, to: :verified do
          guard do
            created_at > verification_window
          end
        end
      end

      event :mark_expired do
        transitions from: :verified, to: :expired
      end
    end

    scope :verified, -> { where(aasm_state: :verified) }
    scope :active, -> { verified }
  end

  # Override in subclasses if needed
  def verification_window
    15.minutes.ago
  end

  # Override in subclasses to implement verification logic
  def verify_code(code, **options)
    raise NotImplementedError, "#{self.class.name} must implement #verify_code"
  end

  # Human-readable name for this 2FA method
  def method_name
    self.class.name.demodulize.titleize
  end

  # Icon or emoji for this 2FA method (override in subclasses)
  def method_icon
    "private"
  end

  # Whether this method can be used as primary authentication
  def can_be_primary?
    true
  end
end
