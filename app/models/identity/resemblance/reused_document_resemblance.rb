# == Schema Information
#
# Table name: identity_resemblances
#
#  id               :bigint           not null, primary key
#  type             :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  document_id      :bigint
#  identity_id      :bigint           not null
#  past_document_id :bigint
#  past_identity_id :bigint           not null
#
# Indexes
#
#  index_identity_resemblances_on_document_id       (document_id)
#  index_identity_resemblances_on_identity_id       (identity_id)
#  index_identity_resemblances_on_past_document_id  (past_document_id)
#  index_identity_resemblances_on_past_identity_id  (past_identity_id)
#
# Foreign Keys
#
#  fk_rails_...  (document_id => identity_documents.id)
#  fk_rails_...  (identity_id => identities.id)
#  fk_rails_...  (past_document_id => identity_documents.id)
#  fk_rails_...  (past_identity_id => identities.id)
#
class Identity::Resemblance::ReusedDocumentResemblance < Identity::Resemblance
  belongs_to :document, class_name: "Identity::Document"
  belongs_to :past_document, class_name: "Identity::Document"

  def title = "document reuse"
  def current_label = document.document_type.humanize
  def matched_label = past_identity.full_name
  def matched_verification = past_document.verification
end
