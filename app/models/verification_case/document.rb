# a raw evidence artifact on a case: user-submitted doc, persona capture,
# or the call recording. all of it lands in encrypted storage; access
# goes through break-glass and is logged.
class VerificationCase::Document < ApplicationRecord
  self.table_name = "verification_case_documents"

  acts_as_paranoid

  belongs_to :verification_case
  has_one_attached :file
  has_many :break_glass_records, as: :break_glassable, class_name: "BreakGlassRecord", dependent: :destroy

  # BreakGlassRecord's activity tracking resolves its recipient via
  # break_glassable.identity — ours lives on the case
  delegate :identity, to: :verification_case

  DOCUMENT_KINDS = {
    "primary_doc" => "Primary document",
    "corroborating_doc" => "Corroborating document",
    "persona_capture" => "Persona capture",
    "selfie" => "Selfie",
    "call_recording" => "Call recording"
  }.freeze

  enum :document_kind, DOCUMENT_KINDS.keys.index_by(&:itself)
  enum :source, %w[persona direct_upload call_recording].index_by(&:itself), prefix: :from

  validates :file, presence: true
  validate :file_size_and_type

  def kind_label = DOCUMENT_KINDS[document_kind]

  private

  def file_size_and_type
    return unless file.attached?

    errors.add(:file, "is too large (maximum is 100MB)") if file.byte_size > 100.megabytes

    allowed = %w[image/jpeg image/png image/jpg image/heic image/heif application/pdf video/mp4 video/webm audio/mpeg]
    unless file.content_type.in?(allowed)
      errors.add(:file, "must be a JPEG, PNG, HEIC, PDF, or recording file")
    end
  end
end
