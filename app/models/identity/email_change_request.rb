# == Schema Information
#
# Table name: identity_email_change_requests
#
#  id                        :bigint           not null, primary key
#  cancelled_at              :datetime
#  completed_at              :datetime
#  expires_at                :datetime         not null
#  new_email                 :string           not null
#  new_email_token_bidx      :string
#  new_email_token_ciphertext :text
#  new_email_verified_at     :datetime
#  old_email                 :string           not null
#  old_email_token_bidx      :string
#  old_email_token_ciphertext :text
#  old_email_verified_at     :datetime
#  requested_from_ip         :string
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  identity_id               :bigint           not null
#
# Indexes
#
#  idx_email_change_requests_identity_completed             (identity_id,completed_at)
#  index_identity_email_change_requests_on_identity_id      (identity_id)
#  index_identity_email_change_requests_on_new_email_token_bidx (new_email_token_bidx)
#  index_identity_email_change_requests_on_old_email_token_bidx (old_email_token_bidx)
#
# Foreign Keys
#
#  fk_rails_...  (identity_id => identities.id)
#
class Identity::EmailChangeRequest < ApplicationRecord
  include PublicIdentifiable

  EXPIRATION = 24.hours

  set_public_id_prefix "emc"

  has_paper_trail

  belongs_to :identity

  alias_method :to_param, :public_id

  has_encrypted :old_email_token
  blind_index :old_email_token

  has_encrypted :new_email_token
  blind_index :new_email_token

  validates :new_email, :old_email, :expires_at, presence: true
  validate :validate_new_email
  validate :new_email_not_taken
  validate :new_email_different_from_old

  scope :pending, -> { where(completed_at: nil, cancelled_at: nil).where("expires_at > ?", Time.current) }
  scope :completed, -> { where.not(completed_at: nil) }

  before_validation :set_defaults, on: :create
  before_create :generate_tokens
  after_create :track_email_change_requested

  def pending?
    completed_at.nil? && cancelled_at.nil? && !expired?
  end

  def completed?
    completed_at.present?
  end

  def cancelled?
    cancelled_at.present?
  end

  def expired?
    expires_at < Time.current
  end

  def old_email_verified?
    old_email_verified_at.present?
  end

  def new_email_verified?
    new_email_verified_at.present?
  end

  def both_emails_verified?
    old_email_verified? && new_email_verified?
  end

  def verify_old_email!(token)
    return false unless pending?
    return false unless ActiveSupport::SecurityUtils.secure_compare(old_email_token.to_s, token.to_s)

    update!(old_email_verified_at: Time.current)
    identity.create_activity :email_change_verified_old,
      owner: identity,
      recipient: identity,
      parameters: { old_email: old_email, new_email: new_email }
    complete_if_ready!
    true
  end

  def verify_new_email!(token)
    return false unless pending?
    return false unless ActiveSupport::SecurityUtils.secure_compare(new_email_token.to_s, token.to_s)

    update!(new_email_verified_at: Time.current)
    identity.create_activity :email_change_verified_new,
      owner: identity,
      recipient: identity,
      parameters: { old_email: old_email, new_email: new_email }
    complete_if_ready!
    true
  end

  def cancel!
    return false unless pending?

    update!(cancelled_at: Time.current)
    true
  end

  def complete_if_ready!
    with_lock do
      return unless both_emails_verified?
      return unless pending?
      return if completed?

      identity.update!(primary_email: new_email)
      update!(completed_at: Time.current)
      identity.create_activity :email_changed,
        owner: identity,
        recipient: identity,
        parameters: { old_email: old_email, new_email: new_email }
    end

    EmailChangeMailer.email_changed_notification(self).deliver_later
  end

  def send_verification_emails!
    EmailChangeMailer.verify_old_email(self).deliver_later
    EmailChangeMailer.verify_new_email(self).deliver_later
  end

  private

  def set_defaults
    self.expires_at ||= EXPIRATION.from_now
    self.old_email ||= identity&.primary_email
  end

  def generate_tokens
    self.old_email_token ||= SecureRandom.urlsafe_base64(32)
    self.new_email_token ||= SecureRandom.urlsafe_base64(32)
  end

  def new_email_not_taken
    return unless new_email.present?

    existing = Identity.where.not(id: identity_id).find_by(primary_email: new_email.downcase)
    errors.add(:new_email, "is already taken by another account") if existing
  end

  def new_email_different_from_old
    return unless new_email.present? && old_email.present?

    if new_email.downcase == old_email.downcase
      errors.add(:new_email, "can't be your current email, ya goof!")
    end
  end

  def track_email_change_requested
    identity.create_activity :email_change_requested,
      owner: identity,
      recipient: identity,
      parameters: { old_email: old_email, new_email: new_email }
  end

  def validate_new_email
    return unless new_email.present?

    address = ValidEmail2::Address.new(new_email)

    unless address.valid?
      errors.add(:new_email, I18n.t("errors.attributes.new_email.invalid_format", default: "is invalid"))
      return
    end

    if address.disposable?
      errors.add(:new_email, I18n.t("errors.attributes.new_email.temporary", default: "cannot be a temporary email"))
      return
    end

    unless address.valid_mx?
      errors.add(:new_email, I18n.t("errors.attributes.new_email.no_mx_record", default: "domain does not accept email"))
    end
  end
end
