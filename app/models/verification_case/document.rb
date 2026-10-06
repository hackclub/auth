# a raw evidence artifact on a case: user-submitted doc, persona capture,
# or the staff screenshot from the call. all of it lands in encrypted storage; access
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
    "call_screenshot" => "Call screenshot"
  }.freeze

  # what may be stored on a case, whatever the upload path. persona captures
  # are sniffed against this before they're attached.
  ALLOWED_CONTENT_TYPES = %w[image/jpeg image/png image/jpg image/heic image/heif application/pdf].freeze

  enum :document_kind, DOCUMENT_KINDS.keys.index_by(&:itself)
  enum :source, %w[persona direct_upload staff_upload].index_by(&:itself), prefix: :from

  validates :file, presence: true
  validate :file_size_and_type
  # the staff screenshot is a still image of the call, nothing else
  validate :screenshot_is_image, if: :call_screenshot?

  def kind_label = DOCUMENT_KINDS[document_kind]

  private

  def screenshot_is_image
    return unless file.attached?

    errors.add(:file, "must be a JPEG or PNG screenshot") unless file.content_type.in?(%w[image/jpeg image/png image/jpg])
  end

  def file_size_and_type
    return unless file.attached?

    errors.add(:file, "is too large (maximum is 25MB)") if file.byte_size > 25.megabytes

    unless file.content_type.in?(ALLOWED_CONTENT_TYPES)
      errors.add(:file, "must be a JPEG, PNG, HEIC, or PDF")
    end
  end
end
