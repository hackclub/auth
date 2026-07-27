# the user side of a manual verification call case. gated three ways:
# logged in (ApplicationController), flipper flag on the identity, and
# a single-use emailed link consumed on first visit.
class ManualVerificationsController < ApplicationController
  before_action :set_case
  before_action :require_case_access

  def show
    @document_class_selected = @case.document_class.present?
    @documents = @case.documents.where.not(source: "call_recording")
  end

  def choose_document_class
    unless @case.link_sent?
      redirect_to manual_verification_path and return
    end

    document_class = params[:document_class]
    unless %w[government_id alternative].include?(document_class)
      flash[:error] = "Pick one of the two options"
      redirect_to manual_verification_path and return
    end

    # the alternative-docs path gets one more nudge back toward government ID
    if document_class == "alternative" && params[:nudge_confirmed] != "true"
      @show_alternative_nudge = true
      @documents = @case.documents.where.not(source: "call_recording")
      render :show and return
    end

    alternative = document_class == "alternative"
    @case.update!(
      document_class: document_class,
      alternative_reason: alternative ? params[:alternative_reason] : nil,
      alternative_reason_details: alternative ? params[:alternative_reason_details] : nil
    )
    @case.log_event!(:document_class_selected, actor: current_identity, request: request,
      data: { document_class: document_class, reason: (params[:alternative_reason] if alternative) }.compact)

    redirect_to manual_verification_path
  rescue ActiveRecord::RecordInvalid => e
    flash[:error] = e.record.errors.full_messages.to_sentence
    redirect_to manual_verification_path
  end

  # launch the embedded persona capture-only inquiry (if a template is
  # configured for this document class — otherwise the direct upload form is shown)
  def start_capture
    unless @case.link_sent? && @case.document_class.present? && !@case.skip_persona?
      redirect_to manual_verification_path and return
    end

    if @case.persona_inquiry_id.blank?
      inquiry = @case.generate_capture_inquiry!
      if inquiry.nil?
        flash[:info] = "Direct upload it is — no capture flow configured for this document class"
        redirect_to manual_verification_path and return
      end
      @case.log_event!(:capture_inquiry_created, actor: current_identity, request: request,
        data: { inquiry_id: @case.persona_inquiry_id })
    end

    @session_token = @case.persona_session_token
    @inquiry_id = @case.persona_inquiry_id
    @environment_id = Rails.application.credentials.dig(:persona, :environment_id)
    @persona_host = Rails.application.credentials.dig(:persona, :host)
    render :capture
  rescue Persona::APIError => e
    Sentry.capture_exception(e, tags: { component: "persona" })
    flash[:error] = "Couldn't start the capture flow — you can upload directly instead"
    redirect_to manual_verification_path
  end

  # direct upload fallback for either document class
  def submit_documents
    unless @case.link_sent? && @case.document_class.present?
      redirect_to manual_verification_path and return
    end

    unless params[:attested] == "1" && params[:biometric_consent] == "1"
      flash[:error] = "Both the attestation and the consent checkbox are required"
      redirect_to manual_verification_path and return
    end

    if params[:primary_doc].blank?
      flash[:error] = "A document is required"
      redirect_to manual_verification_path and return
    end

    # skip-persona cases are camera-capture only — a JPEG/PNG straight from
    # the camera widget, never an arbitrary uploaded file
    if @case.skip_persona? && !params[:primary_doc].content_type.to_s.match?(%r{\Aimage/(jpeg|png)\z})
      flash[:error] = "Your document photo has to come from your camera"
      redirect_to manual_verification_path and return
    end

    ActiveRecord::Base.transaction do
      @case.update!(
        attested: true,
        biometric_consent: true,
        submitted_fields: submitted_fields
      )

      primary = @case.documents.new(document_kind: "primary_doc", source: "direct_upload")
      primary.file.attach(params[:primary_doc])
      primary.save!

      @case.submit_docs!
    end

    @case.log_event!(:docs_submitted, actor: current_identity, request: request,
      data: { source: "direct_upload", fields: submitted_fields.keys })

    flash[:success] = "Documents received — book your call below"
    redirect_to manual_verification_path
  rescue ActiveRecord::RecordInvalid => e
    flash[:error] = e.record.errors.full_messages.to_sentence
    redirect_to manual_verification_path
  end

  # recording disclosure must be acknowledged before the booking link shows
  def acknowledge_recording
    unless @case.booking_available?
      redirect_to manual_verification_path and return
    end

    @case.update!(recording_consent_acknowledged: true)
    @case.log_event!(:recording_consent_acknowledged, actor: current_identity, request: request)

    redirect_to manual_verification_path
  end

  private

  def set_case
    unless Flipper.enabled?(VerificationCase::FLIPPER_FLAG, current_identity)
      redirect_to root_path and return
    end

    @case = current_identity.verification_cases.open_cases.order(created_at: :desc).first
    redirect_to root_path if @case.nil?
  end

  # first visit must carry the emailed single-use token; after it's been
  # consumed the authenticated session is enough.
  def require_case_access
    return if performed?
    return if @case.access_token_used_at.present?

    if @case.consume_access_token!(params[:token])
      @case.log_event!(:link_consumed, actor: current_identity, request: request)
      redirect_to manual_verification_path if params[:token].present? && request.get?
    else
      @case.log_event!(:link_rejected, actor: current_identity, request: request)
      render :link_invalid, status: :forbidden
    end
  end

  def submitted_fields
    params.permit(:legal_name, :date_of_birth, :country, :address, :document_type, :issuing_authority)
      .to_h.compact_blank
  end
end
