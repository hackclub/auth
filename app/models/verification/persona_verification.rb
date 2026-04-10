class Verification::PersonaVerification < Verification
  belongs_to :persona_record, class_name: "Identity::PersonaRecord", optional: true

  encrypts :persona_session_token

  validates :rejection_reason, presence: true, if: :rejected?
  validate :rejection_reason_details_present_when_reason_other

  aasm column: :status, timestamps: true, whiny_transitions: true do
    state :draft, initial: true
    state :pending
    state :approved
    state :rejected

    event :mark_pending do
      transitions from: :draft, to: :pending

      after do
        Identity::NoticeResemblancesJob.perform_later(identity)
        Verification::CheckDiscrepanciesJob.perform_later(self)
      end
    end

    event :approve do
      transitions from: :pending, to: :approved

      after do
        set_ysws_eligibility!
        VerificationMailer.approved(self).deliver_later
      end
    end

    event :mark_as_rejected do
      transitions from: [ :draft, :pending ], to: :rejected

      before do |reason, details = nil|
        self.rejection_reason = reason
        self.rejection_reason_details = details
        self.fatal = fatal_rejection_reason?(reason)
      end

      after do
        if fatal_rejection?
          VerificationMailer.rejected_permanently(self).deliver_later
          Slack::NotifyGuardiansJob.perform_later(identity)
        else
          VerificationMailer.rejected_amicably(self).deliver_later
        end
      end
    end
  end

  enum :rejection_reason, {
    # Retryable
    poor_quality: "poor_quality",
    blurry: "blurry",
    expired: "expired",
    under_13: "under_13",
    other: "other",
    # Fatal
    info_mismatch: "info_mismatch",
    altered: "altered",
    duplicate: "duplicate",
    fraud: "fraud"
  }

  RETRYABLE_REJECTION_REASONS = %w[poor_quality blurry expired under_13 other].freeze
  FATAL_REJECTION_REASONS = %w[info_mismatch altered duplicate fraud].freeze

  REJECTION_REASON_NAMES = {
    "poor_quality" => "Poor image quality",
    "blurry" => "Image too blurry to read",
    "expired" => "Expired document",
    "under_13" => "Submitter is under 13 years old",
    "other" => "Other fixable issue",
    "info_mismatch" => "Information doesn't match profile",
    "altered" => "Document appears altered/fraudulent",
    "duplicate" => "This identity is a duplicate",
    "fraud" => "Fraudulent submission"
  }.freeze

  def rejection_reason_name = REJECTION_REASON_NAMES[rejection_reason] || rejection_reason

  def document_type_label = "Government ID (Persona)"

  def review_info_partial = "backend/verifications/review_persona_info"
  def review_full_partial = "backend/verifications/review_persona_full"
  def relevant_record = persona_record

  def rejection_reason_options
    {
      retryable: RETRYABLE_REJECTION_REASONS.map { |r| [ REJECTION_REASON_NAMES[r], r ] },
      fatal: FATAL_REJECTION_REASONS.map { |r| [ REJECTION_REASON_NAMES[r], r ] }
    }
  end

  def generate_inquiry!
    raise "this verification already has an inquiry!" if persona_inquiry_id.present?

    inquiry = Persona.instance.create_inquiry(
      template_id: Rails.application.credentials.persona.template_id,
      account_reference_id: identity.public_id
    )

    update!(
      persona_inquiry_id: inquiry.id,
      persona_session_token: inquiry.session_token
    )

    identity.update!(persona_account_id: inquiry.account_id) if identity.persona_account_id.blank?

    inquiry
  end

  private

  def fatal_rejection_reason?(reason)
    return false if reason.blank?
    super(reason) || FATAL_REJECTION_REASONS.include?(reason.to_s)
  end

  def rejection_reason_details_present_when_reason_other
    if rejection_reason == "other" && rejection_reason_details.blank?
      errors.add(:rejection_reason_details, "must be provided when rejection reason is 'other'")
    end
  end

  def set_ysws_eligibility!
    return unless persona_record&.birthdate

    age = Identity.calculate_age(persona_record.birthdate)
    identity.update!(ysws_eligible: age >= 13 && age <= 19)
  end
end
