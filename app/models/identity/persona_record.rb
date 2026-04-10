class Identity::PersonaRecord < ApplicationRecord
  acts_as_paranoid

  belongs_to :identity

  has_one :verification, class_name: "Verification::PersonaVerification", foreign_key: "persona_record_id", dependent: :destroy

  encrypts :raw_json_response

  has_many_attached :liveness_images
  has_many :break_glass_records, as: :break_glassable, dependent: :destroy

  validates :inquiry_id, presence: true, uniqueness: true
  validates :raw_json_response, presence: true
  validates :name_first, presence: true
  validates :name_last, presence: true
  validates :birthdate, presence: true
  validates :country_code, presence: true

  def doc_json
    JSON.parse(raw_json_response.strip, symbolize_names: true)
  end
end
