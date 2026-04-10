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
  include Verification::Rejectable

  belongs_to :aadhaar_record, class_name: "Identity::AadhaarRecord", foreign_key: "aadhaar_record_id", optional: true

  validates_presence_of :aadhaar_hc_transaction_id
  before_validation :generate_local_transaction_id, on: :create

  rejection_reasons(
    invalid_format:      { name: "Invalid Aadhaar format",                    fatal: false },
    service_unavailable: { name: "Aadhaar verification service unavailable",  fatal: false },
    under_13:            { name: "Submitter is under 13 years old",           fatal: false },
    other:               { name: "Other fixable issue",                       fatal: false },
    info_mismatch:       { name: "Aadhaar information doesn't match profile", fatal: true },
    duplicate:           { name: "This Aadhaar number is already registered", fatal: true }
  )

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
      before { |reason, details| set_rejection_fields(reason, details) }
      after  { notify_rejection }
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

  # polymorphic interface
  def document_type_label = "Aadhaar"
  def review_info_partial = "backend/shared/review_aadhaar_info"
  def review_full_partial = "backend/shared/review_aadhaar_full"
  def relevant_record     = aadhaar_record
  def needs_break_glass?  = true

  private

  def generate_local_transaction_id
    self.aadhaar_hc_transaction_id = "HC!#{SecureRandom.uuid}"
  end
end
