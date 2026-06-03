module VerificationFlow
  extend ActiveSupport::Concern

  private

  def setup_document_step
    @is_resubmission = @identity.needs_resubmission?
    @rejected_verifications = @identity.rejected_verifications_needing_resubmission if @is_resubmission
    @document = Identity::Document.new(identity: @identity)
  end

  def handle_document_submission
    @document = Identity::Document.new(document_params)
    @document.identity = @identity

    return unless process_legal_name
    return unless process_aadhaar_number

    if @document.save
      create_verification
      on_verification_success
    else
      set_resubmission_context
      on_verification_failure
    end
  end

  def process_legal_name
    legal_first = params[:legal_first_name]
    legal_last = params[:legal_last_name]

    return true unless legal_first.present? && legal_last.present?

    if legal_first != @identity.first_name || legal_last != @identity.last_name
      @identity.legal_first_name = legal_first
      @identity.legal_last_name = legal_last
    else
      @identity.legal_first_name = nil
      @identity.legal_last_name = nil
    end

    if @identity.save
      true
    else
      set_resubmission_context
      @document.errors.add(:base, "Legal name: #{@identity.errors.full_messages.join(', ')}")
      on_verification_failure
      false
    end
  end

  def process_aadhaar_number
    return true unless params[:aadhaar_number].present?

    @identity.aadhaar_number = params[:aadhaar_number]

    if @identity.save
      true
    else
      set_resubmission_context
      @document.errors.add(:base, "Aadhaar number: #{@identity.errors[:aadhaar_number].join(', ')}")
      on_verification_failure
      false
    end
  end

  def set_resubmission_context
    @is_resubmission = @identity.needs_resubmission?
    @rejected_verifications = @identity.rejected_verifications_needing_resubmission if @is_resubmission
  end

  def create_verification
    Verification::DocumentVerification.create!(
      identity: @identity,
      identity_document: @document,
      status: :pending
    )
  end

  def document_params
    params.require(:identity_document).permit(:document_type, files: [])
  end

  def setup_persona_step
    @verification = find_or_create_persona_verification
    @inquiry = @verification.persona_inquiry_id ? reuse_inquiry : create_inquiry

    @inquiry_id = @verification.persona_inquiry_id
    @session_token = @verification.persona_session_token
    @environment_id = Rails.application.credentials.dig(:persona, :environment_id)
    @persona_host = Rails.application.credentials.dig(:persona, :host)
  rescue Persona::APIError => e
    Sentry.capture_exception(e,
      tags: { component: "persona" },
      extra: {
        identity_id: @identity.id,
        identity_public_id: @identity.public_id,
        verification_id: @verification&.id,
        inquiry_id: @verification&.persona_inquiry_id
      })
    @persona_error = I18n.t("verifications.persona.error_message")
  end

  def find_or_create_persona_verification
    @identity.verifications.where(status: :draft, type: "Verification::PersonaVerification").first ||
      Verification::PersonaVerification.create!(identity: @identity)
  end

  def setup_student_id_step
    @verification = find_or_create_student_id_verification
    @inquiry = @verification.persona_inquiry_id ? reuse_inquiry : create_inquiry

    @inquiry_id = @verification.persona_inquiry_id
    @session_token = @verification.persona_session_token
    @environment_id = Rails.application.credentials.dig(:persona, :environment_id)
    @persona_host = Rails.application.credentials.dig(:persona, :host)
  rescue Persona::APIError => e
    Sentry.capture_exception(e,
      tags: { component: "persona" },
      extra: {
        identity_id: @identity.id,
        identity_public_id: @identity.public_id,
        verification_id: @verification&.id,
        inquiry_id: @verification&.persona_inquiry_id
      })
    @persona_error = I18n.t("verifications.persona.error_message")
  end

  def find_or_create_student_id_verification
    @identity.persona_student_id_verifications.where(status: :draft).first ||
      Verification::PersonaStudentIdVerification.create!(identity: @identity)
  end

  def create_inquiry
    @verification.generate_inquiry!
  end

  def reuse_inquiry
    # session token may have expired — refresh it
    inquiry = Persona.instance.resume_inquiry(@verification.persona_inquiry_id)
    @verification.update!(persona_session_token: inquiry.session_token)
    inquiry
  end

  def verification_should_redirect?(status)
    %w[pending verified ineligible].include?(status)
  end
end
