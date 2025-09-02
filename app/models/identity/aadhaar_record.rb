# == Schema Information
#
# Table name: identity_aadhaar_records
#
#  id                :bigint           not null, primary key
#  date_of_birth     :date
#  deleted_at        :datetime
#  name              :string
#  raw_json_response :text
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  identity_id       :bigint           not null
#
# Indexes
#
#  index_identity_aadhaar_records_on_identity_id  (identity_id)
#
# Foreign Keys
#
#  fk_rails_...  (identity_id => identities.id)
#
class Identity::AadhaarRecord < ApplicationRecord
  acts_as_paranoid

  belongs_to :identity

  has_one :verification, class_name: "Verification::AadhaarVerification", foreign_key: "aadhaar_record_id", dependent: :destroy

  encrypts :raw_json_response

  validates :raw_json_response, presence: true
  validates :date_of_birth, presence: true
  validates :name, presence: true

  has_many :break_glass_records, as: :break_glassable, dependent: :destroy

  def doc_json
    JSON.parse(raw_json_response.strip, symbolize_names: true)
  end
end
