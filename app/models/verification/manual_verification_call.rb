# the durable outcome of a manual verification call — created at
# decision time from a VerificationCase. this is the record that
# survives after raw docs and the recording are purged: reviewer,
# checklist, signal snapshot pointer, and (for tier B) an expiry.
class Verification::ManualVerificationCall < Verification
  include Verification::Rejectable

  belongs_to :reviewer, class_name: "Backend::User", optional: true
  belongs_to :sample_reviewer, class_name: "Backend::User", optional: true
  has_one :verification_case, foreign_key: :verification_id

  # every item the reviewer works through on the call, stored as jsonb.
  # confidence + notes ride alongside the y/n answers.
  CHECKLIST_ITEMS = {
    "doc_matches_live_face" => "Document photo matches live face",
    "doc_matches_selfie" => "Document photo matches selfie (persona or live capture)",
    "name_dob_consistent" => "Name/DOB consistent with account records",
    "signals_clean" => "Signals clean (no virtual camera, geo plausible)",
    "doc_unaltered" => "Document appears unaltered"
  }.freeze

  CONFIDENCE_LEVELS = %w[high medium low].freeze

  validates :reviewer, presence: true
  validate :checklist_complete, if: -> { approved? || rejected? }

  rejection_reasons(
    identity_not_confirmed: { name: "Could not confirm identity on the call", fatal: false },
    docs_insufficient:      { name: "Documents insufficient or unreadable",   fatal: false },
    no_show:                { name: "Did not attend the scheduled call",      fatal: false },
    other:                  { name: "Other fixable issue",                    fatal: false },
    info_mismatch:          { name: "Information doesn't match profile",      fatal: true },
    altered:                { name: "Document appears altered/fraudulent",    fatal: true },
    duplicate:              { name: "This identity is a duplicate",           fatal: true },
    fraud:                  { name: "Fraudulent submission",                  fatal: true }
  )

  aasm column: :status, timestamps: true, whiny_transitions: true, whiny_persistence: true do
    state :pending, initial: true
    state :approved
    state :rejected

    event :approve do
      transitions from: :pending, to: :approved
    end

    event :mark_as_rejected do
      transitions from: :pending, to: :rejected
      before { |reason, details| set_rejection_fields(reason, details) }
      after  { notify_rejection }
    end
  end

  def confidence = checklist&.dig("confidence")
  def reviewer_notes = checklist&.dig("notes")

  def checklist_answer(item) = checklist&.dig(item)

  # tier A approvals never expire; tier B gets a 12-month backstop.
  # nullable by design so the policy can change without a migration.
  def expired? = expires_at.present? && expires_at.past?


  # polymorphic interface
  def document_type_label = "Manual verification call"
  def review_info_partial = "backend/verifications/review_manual_call_info"
  def review_full_partial = "backend/verifications/review_manual_call_full"
  def relevant_record     = verification_case
  def needs_break_glass?      = false
  def auto_break_glass_reason = nil
  def status_pending_partial  = "verifications/status/pending_document"
  def auto_approvable?        = false

  private

  def checklist_complete
    missing = CHECKLIST_ITEMS.keys.reject { |k| checklist&.key?(k) }
    errors.add(:checklist, "is missing answers: #{missing.join(', ')}") if missing.any?

    unless CONFIDENCE_LEVELS.include?(checklist&.dig("confidence"))
      errors.add(:checklist, "must record a confidence level")
    end
  end
end
