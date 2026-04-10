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
      when :persona  then redirect_to portal_verify_persona_path
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

  def update_legal_name
    @identity = current_identity
    verf = @identity.persona_verifications.where(status: :draft).first

    unless verf
      redirect_to portal_verify_persona_path
      return
    end

    @identity.update!(
      legal_first_name: params[:legal_first_name].presence || @identity.first_name,
      legal_last_name: params[:legal_last_name].presence || @identity.last_name
    )

    if verf.persona_inquiry_id.present?
      begin
        Persona.instance.expire_inquiry(verf.persona_inquiry_id)
      rescue Persona::APIError
      end
      verf.update!(persona_inquiry_id: nil, persona_session_token: nil)
    end

    redirect_to portal_verify_persona_path
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
