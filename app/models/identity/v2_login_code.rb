class Identity::V2LoginCode < ApplicationRecord
  EXPIRATION = 15.minutes

  scope :active, -> { where(used_at: nil, created_at: EXPIRATION.ago..) }

  belongs_to :identity, class_name: "Identity"
  belongs_to :login_attempt, optional: true

  after_initialize :generate_code
  validates :code, presence: true, uniqueness: { conditions: -> { active } }

  def pretty = "H#{code&.scan(/.../)&.join("-")}"

  private

  def generate_code
    return if code.present?

    loop do
      self.code = SecureRandom.random_number(999_999).to_s.ljust(6, "0") # pad with zero(s) if needed
      self.validate
      break unless self.errors[:code].any?
    end
  end
end
