# == Schema Information
#
# Table name: identity_login_codes
#
#  id               :bigint           not null, primary key
#  expires_at       :datetime
#  return_url       :string
#  token_bidx       :string
#  token_ciphertext :text
#  used_at          :datetime
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  identity_id      :bigint           not null
#
# Indexes
#
#  index_identity_login_codes_on_identity_id  (identity_id)
#
# Foreign Keys
#
#  fk_rails_...  (identity_id => identities.id)
#
class Identity::LoginCode < ApplicationRecord
  belongs_to :identity

  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true

  before_validation :generate_token, on: :create
  before_validation :set_expiration, on: :create

  scope :valid, -> { where("expires_at > ? AND used_at IS NULL", Time.current) }

  has_encrypted :token
  blind_index :token

  def mark_used!
    update!(used_at: Time.current)
  end

  def to_param
    token
  end

  def self.generate(identity, return_url: nil)
    # Expire any existing unused codes for this identity
    identity.login_codes.valid.update_all(used_at: Time.current)

    create!(identity: identity, return_url: return_url)
  end

  def active?
    expires_at > Time.current && used_at.nil?
  end

  def expired?
    expires_at <= Time.current
  end

  def used?
    used_at.present?
  end

  private

  def generate_token
    self.token ||= "login.#{SecureRandom.urlsafe_base64(32)}"
  end

  def set_expiration
    self.expires_at ||= 30.minutes.from_now
  end
end
