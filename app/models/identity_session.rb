class IdentitySession < ApplicationRecord
  LAST_SEEN_AT_COOLDOWN = 5.minutes

  # :session_token alone doesn't match the real columns, and the blind index is
  # deterministic — see BrowserSession for the same fix.
  has_paper_trail skip: [ :session_token, :session_token_ciphertext, :session_token_bidx ]
  has_encrypted :session_token
  blind_index :session_token

  belongs_to :identity
  # Nullable while legacy pre-multi-account sessions are still alive; they get
  # adopted into a BrowserSession on their next request.
  belongs_to :browser_session, optional: true
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

  def live? = !expired? && signed_out_at.nil?

  def revoke!(reason: nil)
    now = Time.now
    update!(signed_out_at: now, expires_at: now, revoked_reason: reason)
  end

  # Authentication assurance, derived from this session's own login factors.
  # Never from the browser session, and never from a sibling account.
  #
  # RFC 8176 has no value for an emailed login link/code, so it maps to `otp`
  # alongside TOTP. Lossy, but every alternative is either a lie or a
  # non-standard value relying parties won't recognise.
  AMR_BY_FACTOR = {
    "email" => "otp",
    "legacy_email" => "otp",
    "totp" => "otp",
    "backup_code" => "otp",
    "webauthn" => "hwk"
  }.freeze

  ACR_SINGLE_FACTOR = "urn:hackclub:auth:1"
  ACR_MULTI_FACTOR = "urn:hackclub:auth:2"

  def completed_authentication_factors
    factors = login_attempt&.authentication_factors
    return [] if factors.blank?

    factors.select { |_name, satisfied| satisfied }.keys
  end

  def multi_factor? = completed_authentication_factors.size >= 2

  # nil rather than a guess when there's no factor record — legacy sessions
  # predate LoginAttempt binding, and omitting the claim is honest.
  def amr_values
    factors = completed_authentication_factors
    return nil if factors.empty?

    values = factors.filter_map { |factor| AMR_BY_FACTOR[factor] }.uniq
    values << "mfa" if multi_factor?
    values.presence
  end

  def acr_value
    return nil if completed_authentication_factors.empty?

    multi_factor? ? ACR_MULTI_FACTOR : ACR_SINGLE_FACTOR
  end

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

  def recently_stepped_up?(for_action: nil)
    return false unless last_step_up_at.present? && last_step_up_at > STEP_UP_DURATION.ago

    # If a specific action is required, verify the step-up was for that action
    return true if for_action.nil?

    last_step_up_action == for_action.to_s
  end

  def record_step_up!(action:)
    update!(last_step_up_at: Time.current, last_step_up_action: action.to_s)
  end

  def clear_step_up! = update!(last_step_up_at: nil, last_step_up_action: nil)

  private

  def identity_is_unlocked
    errors.add(:base, "Account is locked") if identity&.locked?
  end
end
