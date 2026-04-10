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
    when :persona  then redirect_to persona_verification_path
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
