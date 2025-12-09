class Portal::VerificationsController < Portal::BaseController
  include VerificationFlow

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

    setup_document_step
    render :document
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
