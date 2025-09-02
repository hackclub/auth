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
class Verification < ApplicationRecord
  acts_as_paranoid

  include AASM
  include PublicActivity::Model

  has_paper_trail

  tracked owner: ->(controller, model) { controller&.user_for_public_activity }, only: [ :create, :ignored ]

  include PublicIdentifiable
  set_public_id_prefix "verif"

  belongs_to :identity
  belongs_to :identity_document, class_name: "Identity::Document", optional: true

  scope :rejected, -> { where(status: "rejected") }
  scope :pending, -> { where(status: "pending") }
  scope :approved, -> { where(status: "approved") }
  scope :fatal_rejections, -> { rejected.where(fatal: true) }
  scope :retryable_rejections, -> { rejected.where(fatal: false) }
  scope :not_ignored, -> { where(ignored_at: nil) }

  def fatal_rejection? = rejected? && fatal?
  def retryable_rejection? = rejected? && !fatal?

  alias_method :to_param, :public_id

  private

  def fatal_rejection_reason?(reason)
    return false if reason.blank?

    reason = reason.to_s.downcase

    %w[
      duplicate
      fraud
    ].include?(reason)
  end
end
