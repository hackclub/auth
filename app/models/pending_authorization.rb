# A parked authorization request, so "use another account" can leave the middle
# of an OIDC or SAML flow, run a full login, and come back with every parameter
# intact.
#
# The URL only ever carries the opaque handle. The request itself is encrypted at
# rest because the payload can include a login_hint.
class PendingAuthorization < ApplicationRecord
  EXPIRATION = 15.minutes
  KINDS = %w[oidc saml].freeze

  has_encrypted :token
  blind_index :token
  has_encrypted :payload, type: :json

  belongs_to :browser_session

  validates :kind, presence: true, inclusion: { in: KINDS }

  scope :active, -> { where(consumed_at: nil).where("expires_at > ?", Time.now) }

  def self.generate_token = SecureRandom.urlsafe_base64

  def self.park!(browser_session:, kind:, payload:)
    # Handles live for 15 minutes and are never read again afterwards. Reaping the
    # browser session's own dead ones here keeps the table bounded without needing
    # a scheduled job.
    browser_session.pending_authorizations.where("expires_at <= ?", Time.now).delete_all

    create!(
      browser_session: browser_session,
      kind: kind.to_s,
      payload: payload,
      token: generate_token,
      expires_at: EXPIRATION.from_now
    )
  end

  # Single use, and only by the browser session that parked it. Both checks
  # happen under a row lock so two tabs can't both resume the same request.
  def self.consume!(token:, browser_session:, kind: nil)
    return nil if token.blank? || browser_session.nil?

    record = active.find_by(token: token)
    return nil if record.nil?

    record.with_lock do
      return nil if record.consumed_at.present?
      return nil if record.browser_session_id != browser_session.id
      return nil if kind.present? && record.kind != kind.to_s

      record.update!(consumed_at: Time.current)
    end

    record
  end

  def expired? = expires_at <= Time.now

  def consumed? = consumed_at.present?
end
