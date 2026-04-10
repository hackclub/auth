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
class Verification::VouchVerification < Verification
  has_one_attached :evidence
  has_many :break_glass_records, as: :break_glassable, class_name: "BreakGlassRecord", dependent: :destroy

  validates :evidence, presence: true

  aasm column: :status, timestamps: true, whiny_transitions: true do
    state :approved, initial: true

    event :approve do
      transitions from: :pending, to: :approved
    end
  end

  def pending?  = false
  def rejected? = false

  # polymorphic interface
  def document_type_label    = "Vouch"
  def review_info_partial    = "backend/verifications/review_vouch_info"
  def review_full_partial    = "backend/verifications/review_vouch_full"
  def relevant_record        = nil
  def needs_break_glass?     = false
  def rejection_reason_name  = rejection_reason
  def rejection_reason_options = { retryable: [], fatal: [] }
end
