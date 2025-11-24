class IdentitySession < ApplicationRecord
  LAST_SEEN_AT_COOLDOWN = 5.minutes

  has_paper_trail skip: [ :session_token ]
  has_encrypted :session_token
  blind_index :session_token

  belongs_to :identity
  has_one :login_attempt, foreign_key: :session_id

  include PublicActivity::Model
  tracked owner: proc { |controller, record| record.identity }, recipient: proc { |controller, record| record.identity }, only: [ :create ]

  scope :expired, -> { where("expires_at <= ?", Time.now) }
  scope :not_expired, -> { where("expires_at > ?", Time.now) }
  scope :recently_expired_within, ->(date) { expired.where("expires_at >= ?", date) }

  after_create_commit do
    if identity.sessions.size == 1
      # UserSessionMailer.first_login(user:).deliver_later
    elsif fingerprint.present? && identity.sessions.excluding(self).where(fingerprint:).none?
      # UserSessionMailer.new_login(user_session: self).deliver_later
    end
  end

  extend Geocoder::Model::ActiveRecord
  geocoded_by :ip
  after_validation :geocode, if: ->(session) { session.ip.present? and session.ip_changed? }

  validate :identity_is_unlocked, on: :create

  def expired? = expires_at <= Time.now

  def clear_metadata!
    update!(
      device_info: nil,
      latitude: nil,
      longitude: nil,
      )
  end

  def touch_last_seen_at
    return if last_seen&.after?(LAST_SEEN_AT_COOLDOWN.ago)
    update_column(:last_seen, Time.current)
  end

  private

  def identity_is_unlocked
    errors.add(:base, "Account is locked") if identity&.locked?
  end
end
