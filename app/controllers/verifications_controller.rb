class VerificationsController < ApplicationController
  include Wicked::Wizard
  include VerificationFlow
  include AhoyAnalytics

  before_action :set_identity

  steps :document

  def new
    status = current_identity.verification_status
    if verification_should_redirect?(status)
      redirect_to verification_status_path
      return
    end

    case current_identity.required_verification_method
    when :persona
      if current_identity.persona_student_id_eligible?
        @persona_path = persona_verification_path
        @student_id_path = student_id_verification_path
        render :choose
      else
        redirect_to persona_verification_path
      end
    when :document then redirect_to verification_step_path(:document)
    end
  end

  def status
    @identity = current_identity
    @status = @identity.verification_status
    @latest_verification = @identity.latest_verification

    # Draft persona/aadhaar verifications mean the user has started an async
    # flow — show "pending" instead of "not started" while we wait for the webhook.
    if @status == "needs_submission" && @identity.verifications.not_ignored.where(status: :draft).any?
      @status = "pending"
    end
  end

  def status_check
    status = current_identity.verification_status
    if status == "needs_submission" && current_identity.verifications.not_ignored.where(status: :draft).any?
      status = "pending"
    end
    render json: { status: }
  end

  def persona
    @identity = current_identity

    status = @identity.verification_status
    if verification_should_redirect?(status)
      redirect_to verification_status_path
      return
    end

    setup_persona_step
    render :persona
  end

  def student_id
    @identity = current_identity

    status = @identity.verification_status
    if verification_should_redirect?(status)
      redirect_to verification_status_path
      return
    end

    unless @identity.persona_student_id_eligible?
      redirect_to persona_verification_path
      return
    end

    setup_student_id_step
    render :persona
  end

  def update_legal_name
    draft = current_identity.persona_verifications.where(status: :draft).first
    redirect_path = draft.is_a?(Verification::PersonaStudentIdVerification) ? student_id_verification_path : persona_verification_path
    handle_legal_name_update(
      redirect_path: redirect_path,
      find_verification: -> { draft }
    )
  end

  def show
    @identity = current_identity

    status = @identity.verification_status
    if verification_should_redirect?(status)
      redirect_to verification_status_path
      return
    end

    if @identity.required_verification_method == :persona && step == :document
      flash[:info] = "We use automated verification now — it's faster!"
      redirect_to persona_verification_path and return
    end

    case step
    when :document
      setup_document_step
    end

    render_wizard
  end

  def update
    @identity = current_identity

    status = @identity.verification_status
    if verification_should_redirect?(status)
      redirect_to verification_status_path
      return
    end

    if @identity.required_verification_method == :persona
      redirect_to persona_verification_path and return
    end

    case step
    when :document
      handle_document_submission
    end
  end

  private

  def set_identity
    @identity = current_identity
  end

  def on_verification_success
    track_event("verification.submitted", verification_type: "document", scenario: analytics_scenario_for(@identity))
    flash[:success] = "Your documents have been submitted for review! We'll email you when they're processed."
    redirect_to root_path
  end

  def on_verification_failure
    render_wizard
  end
end
