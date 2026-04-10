# == Schema Information
#
# Table name: identity_documents
#
#  id            :bigint           not null, primary key
#  deleted_at    :datetime
#  document_type :integer
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  identity_id   :bigint           not null
#
# Indexes
#
#  index_identity_documents_on_deleted_at   (deleted_at)
#  index_identity_documents_on_identity_id  (identity_id)
#
# Foreign Keys
#
#  fk_rails_...  (identity_id => identities.id)
#
class Identity::Document < ApplicationRecord
  acts_as_paranoid

  belongs_to :identity
  has_one :verification, class_name: "Verification::DocumentVerification", foreign_key: "identity_document_id", dependent: :destroy
  has_many_attached :files
  has_many :break_glass_records, as: :break_glassable, class_name: "BreakGlassRecord", dependent: :destroy

  TRANSCRIPT_COUNTRIES = %w[US AU CA SG]

  enum :document_type, {
         government_id: 0,
         transcript: 1,
         persona_gov_id: 2,
         persona_liveness: 3
       }

  FRIENDLY_NAMES = {
    government_id: "Government-issued ID",
    transcript: "Transcript & Student ID",
    persona_gov_id: "Government ID (Persona)",
    persona_liveness: "Liveness Check (Persona)"
  }

  validates :document_type, presence: true
  validates :files, presence: true, on: :create
  validate :correct_number_of_files, on: :create
  validate :file_size_and_type

  def self.selectable_types_for_country(country)
    if TRANSCRIPT_COUNTRIES.include?(country)
      %i[transcript government_id]
    else
      %i[government_id]
    end
  end

  def self.collection_select_options_for_country(country)
    selectable_types_for_country(country).map { |type| [ FRIENDLY_NAMES[type], type ] }
  end

  def current_verification
    verification
  end

  def verification_status
    current_verification&.status || "pending"
  end

  def verified?
    verification_status == "approved"
  end

  def rejected?
    verification_status == "rejected"
  end

  def pending_verification?
    verification_status == "pending"
  end

  private

  def correct_number_of_files
    return unless files.attached?

    actual_count = files.count

    case document_type
    when "transcript"
      errors.add(:files, "must include exactly 2 files") unless actual_count == 2
    when "government_id"
      errors.add(:files, "must include exactly 1 file") unless actual_count == 1
    when "persona_gov_id"
      errors.add(:files, "must include 1 or 2 files") unless actual_count.between?(1, 2)
    when "persona_liveness"
      errors.add(:files, "must include at least 1 file") unless actual_count >= 1
    end
  end

  def file_size_and_type
    return unless files.attached?

    files.each do |file|
      # Check file size (max 10MB)
      if file.byte_size > 10.megabytes
        errors.add(:files, "#{file.filename} is too large (maximum is 10MB)")
      end

      # Check file type
      unless file.content_type.in?(%w[image/jpeg image/png image/jpg image/heic image/heif application/pdf])
        errors.add(:files, "#{file.filename} must be a JPEG, PNG, HEIC, or PDF file")
      end
    end
  end
end
