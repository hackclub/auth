# the durable outcome of a manual verification call — created at
# decision time from a VerificationCase. this is the record that
# the durable decision record alongside the raw evidence: reviewer,
# checklist and signal snapshot pointer.
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

  # qa sampling: every nth decision is queued for a second reviewer to
  # re-read the evidence and say whether they agree. any decided record
  # can also be sampled voluntarily; the queue just picks the nth ones.
  QA_SAMPLE_EVERY = 5
  SAMPLE_VERDICTS = %w[agree disagree].freeze

  validates :reviewer, presence: true
  validate :checklist_complete, if: -> { approved? || rejected? }
  validates :sample_verdict, inclusion: { in: SAMPLE_VERDICTS }, if: -> { sampled_at.present? }
  validates :sample_notes, presence: true, if: -> { sample_verdict == "disagree" }
  validate :sample_reviewer_is_not_the_reviewer, if: -> { sample_reviewer_id.present? }

  scope :decided, -> { where(status: %w[approved rejected]) }
  scope :qa_sampled, -> { where.not(sampled_at: nil) }
  scope :qa_candidates, -> {
    decided.where(sampled_at: nil)
      .where("#{table_name}.id % ? = 0", QA_SAMPLE_EVERY)
      .order(Arel.sql("COALESCE(verifications.approved_at, verifications.rejected_at, verifications.created_at) ASC"))
  }

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

  def decided? = approved? || rejected?
  def sampled? = sampled_at.present?
  def qa_candidate? = decided? && !sampled? && (id % QA_SAMPLE_EVERY).zero?
  def decided_at = approved_at || rejected_at || created_at

  class AlreadySampled < StandardError; end

  # row-locked so two reviewers sampling at once can't both win: the
  # second one re-reads under the lock, sees the sample, and raises
  def record_sample!(reviewer:, verdict:, notes:)
    with_lock do
      raise AlreadySampled, "this decision has already been sampled" if sampled?

      update!(
        sampled_at: Time.current,
        sample_reviewer: reviewer,
        sample_verdict: verdict,
        sample_notes: notes.to_s.strip.presence
      )
    end
  end

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

  def sample_reviewer_is_not_the_reviewer
    errors.add(:sample_reviewer, "can't QA their own decision") if sample_reviewer_id == reviewer_id
  end

  def checklist_complete
    missing = CHECKLIST_ITEMS.keys.reject { |k| checklist&.key?(k) }
    errors.add(:checklist, "is missing answers: #{missing.join(', ')}") if missing.any?

    unless CONFIDENCE_LEVELS.include?(checklist&.dig("confidence"))
      errors.add(:checklist, "must record a confidence level")
    end
  end
end
