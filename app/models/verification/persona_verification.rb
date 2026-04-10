class Verification::PersonaVerification < Verification
  include Verification::Rejectable
  include HasPersonaUrl
  has_persona_url "inquiries", :persona_inquiry_id

  encrypts :persona_session_token

  rejection_reasons(
    poor_quality:  { name: "Poor image quality",                  fatal: false },
    blurry:        { name: "Image too blurry to read",            fatal: false },
    expired:       { name: "Expired document",                    fatal: false },
    under_13:      { name: "Submitter is under 13 years old",     fatal: false },
    other:         { name: "Other fixable issue",                 fatal: false },
    info_mismatch: { name: "Information doesn't match profile",   fatal: true },
    altered:       { name: "Document appears altered/fraudulent", fatal: true },
    duplicate:     { name: "This identity is a duplicate",        fatal: true },
    fraud:         { name: "Fraudulent submission",               fatal: true }
  )

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
      before { |reason, details| set_rejection_fields(reason, details) }
      after  { notify_rejection }
    end
  end

  # polymorphic interface
  def document_type_label = "Government ID (Persona)"
  def review_info_partial = "backend/verifications/review_persona_info"
  def review_full_partial = "backend/verifications/review_persona_full"
  def relevant_record     = persona_record
  def needs_break_glass?  = true

  def generate_inquiry!
    raise "this verification already has an inquiry!" if persona_inquiry_id.present?

    inquiry = Persona.instance.create_inquiry(
      template_id: Rails.application.credentials.persona.template_id,
      account_reference_id: identity.public_id
    )

    update!(persona_inquiry_id: inquiry.id, persona_session_token: inquiry.session_token)
    identity.update!(persona_account_id: inquiry.account_id) if identity.persona_account_id.blank?

    inquiry
  end

  private

  def set_ysws_eligibility!
    return unless persona_record&.birthdate
    age = Identity.calculate_age(persona_record.birthdate)
    identity.update!(ysws_eligible: age.between?(13, 19))
  end
end
