class Portal::VerificationsController < Portal::BaseController
  include VerificationFlow

  before_action :validate_portal_return_url, only: [ :start ]
  before_action :store_return_url, only: [ :start ]

  def start
    @identity = current_identity
    status = @identity.verification_status

    case status
    when "verified"
      redirect_to_portal_return(status: :verified)
    when "pending"
      redirect_to_portal_return(status: :pending)
    else
      case @identity.required_verification_method
      when :persona
        if @identity.persona_student_id_eligible?
          @persona_path = portal_verify_persona_path
          @student_id_path = portal_verify_student_id_path
          render "verifications/choose"
        else
          redirect_to portal_verify_persona_path
        end
      when :document then redirect_to portal_verify_document_path
      end
    end
  end

  def portal
    @identity = current_identity
    status = @identity.verification_status

    case status
    when "verified"
      redirect_to_portal_return(status: :verified)
      return
    when "pending"
      redirect_to_portal_return(status: :pending)
      return
    end

    if @identity.required_verification_method == :persona
      flash[:info] = "We use automated verification now — it's faster!"
      redirect_to portal_verify_persona_path and return
    end

    setup_document_step
    render :document
  end

  def persona
    @identity = current_identity
    status = @identity.verification_status

    case status
    when "verified"
      redirect_to_portal_return(status: :verified)
      return
    when "pending"
      redirect_to_portal_return(status: :pending)
      return
    end

    setup_persona_step
  end

  def student_id
    @identity = current_identity
    status = @identity.verification_status

    case status
    when "verified"
      redirect_to_portal_return(status: :verified)
      return
    when "pending"
      redirect_to_portal_return(status: :pending)
      return
    end

    unless @identity.persona_student_id_eligible?
      redirect_to portal_verify_persona_path
      return
    end

    setup_student_id_step
    render "verifications/persona"
  end

  def update_legal_name
    draft = current_identity.persona_verifications.where(status: :draft).first
    redirect_path = draft.is_a?(Verification::PersonaStudentIdVerification) ? portal_verify_student_id_path : portal_verify_persona_path
    handle_legal_name_update(
      redirect_path: redirect_path,
      find_verification: -> { draft }
    )
  end

  def cancel
    cancel_portal_flow
  end

  def create
    @identity = current_identity

    status = @identity.verification_status
    if status == "pending" || status == "verified"
      redirect_to_portal_return(status: status.to_sym)
      return
    end

    if @identity.required_verification_method == :persona
      redirect_to portal_verify_persona_path and return
    end

    handle_document_submission
  end

  private

  def on_verification_success
    redirect_to_portal_return(status: :submitted)
  end

  def on_verification_failure
    render :document
  end
end
