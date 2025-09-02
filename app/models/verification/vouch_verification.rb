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
  def document_type = "Vouch"

  has_one_attached :evidence
  has_many :break_glass_records, as: :break_glassable, class_name: "BreakGlassRecord", dependent: :destroy

  validates :evidence, presence: true


  aasm column: :status, timestamps: true, whiny_transitions: true do
    state :approved, initial: true

    event :approve do
      transitions from: :pending, to: :approved
    end
  end

  def pending? = false
  def rejected? = false

  def rejection_reason_name = rejection_reason

  private

  def fatal_rejection_reason?(reason) = false

  def rejection_reason_details_present_when_reason_other
    if rejection_reason == "other" && rejection_reason_details.blank?
      errors.add(:rejection_reason_details, "must be provided when rejection reason is 'other'")
    end
  end
end
