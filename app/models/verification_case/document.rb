# a raw evidence artifact on a case: user-submitted doc, persona capture,
# or the call recording. all of it lands in encrypted storage and gets a
# retention_delete_at stamped at decision time — nothing raw lives forever.
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

  validates :file, presence: true, unless: :purged?
  validate :file_size_and_type

  scope :purgeable, -> { where(purged_at: nil).where(retention_delete_at: ..Time.current) }

  def purged? = purged_at.present?

  def kind_label = DOCUMENT_KINDS[document_kind]

  # retention: destroy the blob, keep the row as a tombstone so the
  # decision record still shows what existed.
  def purge_file!
    transaction do
      file.purge if file.attached?
      update!(purged_at: Time.current)
    end
    verification_case.log_event!(:document_purged, data: { document_id: id, kind: document_kind })
  end

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
