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
      # First login - no need to notify
    elsif fingerprint.present? && identity.sessions.where("created_at > ?", 6.months.ago).excluding(self).where(fingerprint:).none?
      IdentitySessionMailer.new_login(self).deliver_later
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

  STEP_UP_DURATION = 15.minutes

  def recently_stepped_up?
    last_step_up_at.present? && last_step_up_at > STEP_UP_DURATION.ago
  end

  def record_step_up!
    update!(last_step_up_at: Time.current)
  end

  def clear_step_up!
    update!(last_step_up_at: nil)
  end

  private

  def identity_is_unlocked
    errors.add(:base, "Account is locked") if identity&.locked?
  end
end
