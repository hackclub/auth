class Identity::V2LoginCode < ApplicationRecord
  EXPIRATION = 15.minutes

  scope :active, -> { where(used_at: nil, invalidated_at: nil, created_at: EXPIRATION.ago..) }

  belongs_to :identity, class_name: "Identity"

  after_initialize :generate_code
  validates :code, presence: true, uniqueness: { conditions: -> { active } }

  def self.generate(identity, **attrs)
    identity.v2_login_codes.active.update_all(invalidated_at: Time.current)
    create!(identity: identity, **attrs)
  end

  def pretty = code&.scan(/.../)&.join("-")

  private

  def generate_code
    return unless has_attribute?(:code)
    return if code.present?

    loop do
      self.code = SecureRandom.random_number(1_000_000).to_s.rjust(6, "0")
      self.validate
      break unless self.errors[:code].any?
    end
  end
end
