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
  include Verification::Rejectable

  belongs_to :identity_document, class_name: "Identity::Document"

  after_create_commit :check_for_resemblances

  rejection_reasons(
    poor_quality:  { name: "Poor image quality",                              fatal: false },
    not_readable:  { name: "Document not readable",                           fatal: false },
    wrong_type:    { name: "Wrong document type",                             fatal: false },
    expired:       { name: "Expired document",                                fatal: false },
    under_13:      { name: "Submitter is under 13 years old",                 fatal: false },
    other:         { name: "Other fixable issue",                             fatal: false },
    info_mismatch: { name: "Information doesn't match profile",               fatal: true },
    altered:       { name: "Document appears altered/fraudulent",             fatal: true },
    duplicate:     { name: "This identity is a duplicate of another identity", fatal: true }
  )

  aasm column: :status, timestamps: true, whiny_transitions: true do
    state :pending, initial: true
    state :approved
    state :rejected

    event :approve do
      transitions from: :pending, to: :approved
    end

    event :mark_as_rejected do
      transitions from: :pending, to: :rejected
      before { |reason, details| set_rejection_fields(reason, details) }
      after  { notify_rejection }
    end
  end

  def document_type
    return nil unless identity_document
    Identity::Document::FRIENDLY_NAMES[identity_document.document_type.to_sym]
  end

  # polymorphic interface
  def document_type_label = document_type || "Document"
  def review_info_partial = "backend/shared/review_document_info"
  def review_full_partial = "backend/shared/review_document_files"
  def relevant_record     = identity_document
  def needs_break_glass?  = true

  private

  def check_for_resemblances
    Identity::NoticeResemblancesJob.perform_later(identity)
  end
end
