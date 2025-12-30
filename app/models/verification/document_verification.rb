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
class Verification::DocumentVerification < Verification
  def document_type
    return nil unless identity_document

    Identity::Document::FRIENDLY_NAMES[identity_document.document_type.to_sym]
  end

  belongs_to :identity_document, class_name: "Identity::Document"

  after_create_commit :check_for_resemblances

  # This is the main verification type for document-based verifications
  # All existing verification functionality lives here

  aasm column: :status, timestamps: true, whiny_transitions: true do
    state :pending, initial: true
    state :approved
    state :rejected

    event :approve do
      transitions from: :pending, to: :approved
    end

    event :mark_as_rejected do
      transitions from: :pending, to: :rejected

      before do |reason, details = nil|
        self.rejection_reason = reason
        self.rejection_reason_details = details

        # Set fatal flag for inherently fatal rejection reasons
        self.fatal = fatal_rejection_reason?(reason)
      end

      after do
        if fatal_rejection?
          VerificationMailer.rejected_permanently(self).deliver_later
          Slack::NotifyGuardiansJob.perform_later(self.identity)
        else
          VerificationMailer.rejected_amicably(self).deliver_later
        end
      end
    end
  end

  # Override to make identity_document required for document verifications

  # Delegate document_type to the associated identity_document


  enum :rejection_reason, {
    # Retry-able issues
    poor_quality: "poor_quality",
    not_readable: "not_readable",
    wrong_type: "wrong_type",
    expired: "expired",
    under_13: "under_13",
    other: "other",
    # Fatal issues
    info_mismatch: "info_mismatch",
    altered: "altered",
    duplicate: "duplicate"
  }

  # Define retry-able vs fatal rejection reasons
  RETRYABLE_REJECTION_REASONS = %w[poor_quality not_readable wrong_type expired under_13 other].freeze
  FATAL_REJECTION_REASONS = %w[info_mismatch altered duplicate].freeze

  # Friendly names for rejection reasons
  REJECTION_REASON_NAMES = {
    # Retry-able issues
    "poor_quality" => "Poor image quality",
    "not_readable" => "Document not readable",
    "wrong_type" => "Wrong document type",
    "expired" => "Expired document",
    "under_13" => "Submitter is under 13 years old",
    "other" => "Other fixable issue",
    # Fatal issues
    "info_mismatch" => "Information doesn't match profile",
    "altered" => "Document appears altered/fraudulent",
    "duplicate" => "This identity is a duplicate of another identity"
  }.freeze

  validates :rejection_reason, presence: true, if: :rejected?
  validate :rejection_reason_details_present_when_reason_other

  def rejection_reason_name = REJECTION_REASON_NAMES[rejection_reason] || rejection_reason

  private

  # Override to include document-specific fatal rejection reasons
  def fatal_rejection_reason?(reason)
    return false if reason.blank?

    reason_str = reason.to_s

    # Include base class fatal reasons plus document-specific ones
    super(reason) || FATAL_REJECTION_REASONS.include?(reason_str)
  end

  def rejection_reason_details_present_when_reason_other
    if rejection_reason == "other" && rejection_reason_details.blank?
      errors.add(:rejection_reason_details, "must be provided when rejection reason details is 'other'")
    end
  end

  def check_for_resemblances
    Identity::NoticeResemblancesJob.perform_later(identity)
  end
end
