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

    redirect_to verification_step_path(:document)
  end

  def status
    @identity = current_identity
    @status = @identity.verification_status
    @latest_verification = @identity.latest_verification
  end

  def show
    @identity = current_identity

    status = @identity.verification_status
    if verification_should_redirect?(status)
      redirect_to verification_status_path
      return
    end

    case step
    when :document
      setup_document_step
    end

    render_wizard
  end

  def update
    @identity = current_identity

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
    track_event("verification.submitted", verification_type: "document")
    flash[:success] = "Your documents have been submitted for review! We'll email you when they're processed."
    redirect_to root_path
  end

  def on_verification_failure
    render_wizard
  end
end
