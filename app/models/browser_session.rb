# A browser session is the thing the cookie points at. It owns one or more
# IdentitySessions — one per signed-in account — and a pointer to whichever one
# is currently active.
#
# Authentication assurance is deliberately NOT stored here. Expiry, step-up and
# login factors all live on the individual IdentitySession, so signing into a
# second account never inherits the first account's 2FA.
class BrowserSession < ApplicationRecord
  # A person with a work and a personal account needs two. Anything past this is
  # not a use case we're supporting, and an unbounded list is a footgun.
  MAX_ACCOUNTS = 5

  LAST_SEEN_AT_COOLDOWN = 5.minutes

  has_paper_trail skip: [ :token ]
  has_encrypted :token
  blind_index :token

  has_many :identity_sessions, dependent: :nullify
  belongs_to :active_identity_session, class_name: "IdentitySession", optional: true
  has_many :client_selections, class_name: "BrowserSession::ClientSelection", dependent: :destroy
  has_many :pending_authorizations, dependent: :destroy

  validate :active_session_belongs_to_this_browser_session

  scope :expired, -> { where("expires_at <= ?", Time.now) }
  scope :not_expired, -> { where("expires_at > ?", Time.now) }

  def self.generate_token = SecureRandom.urlsafe_base64

  def self.start!(expires_at:)
    create!(token: generate_token, expires_at: expires_at)
  end

  def expired? = expires_at <= Time.now

  # Every account currently usable in this browser. Oldest first so the chooser
  # order is stable as accounts come and go.
  def live_identity_sessions
    identity_sessions.not_expired.where(signed_out_at: nil).order(:created_at)
  end

  def live_identities
    Identity.where(id: live_identity_sessions.select(:identity_id))
  end

  def identity_session_for(identity)
    live_identity_sessions.find_by(identity_id: identity.id)
  end

  def account_count = live_identity_sessions.count

  def at_account_limit? = account_count >= MAX_ACCOUNTS

  # The active session may have expired while other accounts are still live. We
  # never silently promote a sibling — that would change `sub` mid-session — so
  # this returns nil and the caller sends the user to the chooser.
  def active_session
    session = active_identity_session
    return nil if session.nil?
    return nil if session.expired? || session.signed_out_at.present?

    session
  end

  def active_identity = active_session&.identity

  def activate!(identity_session)
    unless identity_session.browser_session_id == id
      raise ArgumentError, "identity session does not belong to this browser session"
    end

    update!(active_identity_session: identity_session)
  end

  # Session fixation defence: the cookie value changes whenever the set of
  # accounts in this browser changes, without disturbing the accounts themselves.
  def rotate_token!
    update!(token: self.class.generate_token)
    token
  end

  def extend_expiry!(new_expires_at)
    return if expires_at.present? && expires_at >= new_expires_at

    update!(expires_at: new_expires_at)
  end

  def touch_last_seen_at
    return if last_seen&.after?(LAST_SEEN_AT_COOLDOWN.ago)

    update_column(:last_seen, Time.current)
  end

  def selection_for(kind:, ref:)
    client_selections.find_by(client_kind: kind.to_s, client_ref: ref.to_s)
  end

  def remember_selection!(kind:, ref:, identity:)
    selection = client_selections.find_or_initialize_by(client_kind: kind.to_s, client_ref: ref.to_s)
    selection.identity = identity
    selection.last_used_at = Time.current
    selection.save!
    selection
  rescue ActiveRecord::RecordNotUnique
    # Concurrent tabs raced us to the unique index; theirs is as good as ours.
    retry
  end

  # Sticky selections point at identities, so a remembered account may no longer
  # have a live session here. Callers treat that as "no selection" but can still
  # preselect it in the chooser.
  def remembered_identity_session(kind:, ref:)
    identity_id = selection_for(kind: kind, ref: ref)&.identity_id
    return nil unless identity_id

    live_identity_sessions.find_by(identity_id: identity_id)
  end

  def revoke_all!(reason:)
    live_identity_sessions.each { |s| s.revoke!(reason: reason) }
    update!(active_identity_session: nil)
  end

  private

  def active_session_belongs_to_this_browser_session
    return if active_identity_session_id.nil?
    return if active_identity_session&.browser_session_id == id

    errors.add(:active_identity_session, "must belong to this browser session")
  end
end
