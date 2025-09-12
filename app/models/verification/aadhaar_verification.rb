# == Schema Information
#
# Table name: verifications
#
#  id                              :bigint           not null, primary key
#  aadhaar_link                    :string
#  approved_at                     :datetime
#  deleted_at                      :datetime
#  fatal                           :boolean          default(FALSE), not null
#  ignored_at                      :datetime
#  ignored_reason                  :string
#  internal_rejection_comment      :text
#  issues                          :string           default([]), is an Array
#  pending_at                      :datetime
#  rejected_at                     :datetime
#  rejection_reason                :string
#  rejection_reason_details        :string
#  status                          :string           not null
#  type                            :string
#  created_at                      :datetime         not null
#  updated_at                      :datetime         not null
#  aadhaar_external_transaction_id :string
#  aadhaar_hc_transaction_id       :string
#  aadhaar_record_id               :bigint
#  identity_document_id            :bigint
#  identity_id                     :bigint           not null
#
# Indexes
#
#  index_verifications_on_aadhaar_record_id     (aadhaar_record_id)
#  index_verifications_on_deleted_at            (deleted_at)
#  index_verifications_on_fatal                 (fatal)
#  index_verifications_on_identity_document_id  (identity_document_id)
#  index_verifications_on_identity_id           (identity_id)
#  index_verifications_on_type                  (type)
#
# Foreign Keys
#
#  fk_rails_...  (aadhaar_record_id => identity_aadhaar_records.id)
#  fk_rails_...  (identity_document_id => identity_documents.id)
#  fk_rails_...  (identity_id => identities.id)
#
class Verification::AadhaarVerification < Verification
  def document_type = "Aadhaar"

  belongs_to :aadhaar_record, class_name: "Identity::AadhaarRecord", foreign_key: "aadhaar_record_id", optional: true

  validates_presence_of :aadhaar_hc_transaction_id
  before_validation :generate_local_transaction_id, on: :create
  validates :rejection_reason, presence: true, if: :rejected?
  validate :rejection_reason_details_present_when_reason_other

  aasm column: :status, timestamps: true, whiny_transitions: true do
    state :draft, initial: true
    state :pending
    state :approved
    state :rejected

    event :mark_pending do
      transitions from: :draft, to: :pending

      after do
        Verification::CheckDiscrepanciesJob.perform_later(self)
      end
    end

    event :approve do
      transitions from: :pending, to: :approved
    end

    event :mark_as_rejected do
      transitions from: [ :draft, :pending ], to: :rejected

      before do |reason, details = nil|
        self.rejection_reason = reason
        self.rejection_reason_details = details

        self.fatal = fatal_rejection_reason?(reason)
      end

      after do
        if fatal_rejection?
          VerificationMailer.rejected_permanently(self).deliver_later
          Slack::NotifyGuardiansJob.perform_later(@verification.identity)
        else
          VerificationMailer.rejected_amicably(self).deliver_later
        end
      end
    end
  end

  def generate_link!(callback_url:, redirect_url:)
    raise "this verification already has a link!" if aadhaar_link.present?

    data = AadhaarService.instance.generate_step_1_link(
      callback_url:, redirect_url:,
      trans_id: aadhaar_hc_transaction_id,
    )

    raise "error!: #{data[:msg]}" unless data[:status] == 1

    update!(
      aadhaar_link: data[:data][:url],
      aadhaar_external_transaction_id: data[:ts_trans_id]
    )

    create_activity("create_link")
  end

  enum :rejection_reason, {
    # Retry-able issues
    invalid_format: "invalid_format",
    service_unavailable: "service_unavailable",
    under_13: "under_13",
    other: "other",
    # Fatal issues
    info_mismatch: "info_mismatch",
    duplicate: "duplicate"
  }

  # Define retry-able vs fatal rejection reasons
  RETRYABLE_REJECTION_REASONS = %w[invalid_format service_unavailable 13 other].freeze
  FATAL_REJECTION_REASONS = %w[info_mismatch duplicate].freeze

  # Friendly names for rejection reasons
  REJECTION_REASON_NAMES = {
    # Retry-able issues
    "invalid_format" => "Invalid Aadhaar format",
    "service_unavailable" => "Aadhaar verification service unavailable",
    "under_13" => "Submitter is under 13 years old",
    "other" => "Other fixable issue",
    # Fatal issues
    "info_mismatch" => "Aadhaar information doesn't match profile",
    "duplicate" => "This Aadhaar number is already registered"
  }.freeze

  def rejection_reason_name = REJECTION_REASON_NAMES[rejection_reason] || rejection_reason

  private

  # Override to include Aadhaar-specific fatal rejection reasons
  def fatal_rejection_reason?(reason)
    return false if reason.blank?

    reason_str = reason.to_s

    super(reason) || FATAL_REJECTION_REASONS.include?(reason_str)
  end

  def rejection_reason_details_present_when_reason_other
    if rejection_reason == "other" && rejection_reason_details.blank?
      errors.add(:rejection_reason_details, "must be provided when rejection reason is 'other'")
    end
  end

  def generate_local_transaction_id
    self.aadhaar_hc_transaction_id = "HC!#{SecureRandom.uuid}"
  end
end
