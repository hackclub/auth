# the user side of a manual verification call case. gated three ways:
# logged in (ApplicationController), flipper flag on the identity, and
# a single-use emailed link consumed on first visit.
class ManualVerificationsController < ApplicationController
  before_action :set_case
  before_action :require_case_access

  def show
    @document_class_selected = @case.document_class.present?
    @documents = @case.documents.where.not(source: "staff_upload")
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
      @documents = @case.documents.where.not(source: "staff_upload")
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

  # the persona capture collects face geometry, so the same attestation,
  # biometric consent and submitted fields the direct upload requires are
  # recorded on the case BEFORE the capture inquiry can be started
  def prepare_capture
    unless @case.link_sent? && @case.document_class.present? && @case.persona_capture_available?
      redirect_to manual_verification_path and return
    end

    return unless submission_prerequisites_present?

    @case.update!(attested: true, biometric_consent: true, submitted_fields: submitted_fields)
    @case.log_event!(:capture_prerequisites_recorded, actor: current_identity, request: request,
      data: { fields: submitted_fields.keys })

    redirect_to manual_verification_capture_path
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

    unless @case.docs_submission_prerequisites_met?
      flash[:error] = "Fill in your document details and tick both boxes before scanning"
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

    return unless submission_prerequisites_present?

    if params[:primary_doc].blank?
      flash[:error] = "A document is required"
      redirect_to manual_verification_path and return
    end

    if @case.skip_persona? && params[:selfie].blank?
      flash[:error] = "A selfie is required"
      redirect_to manual_verification_path and return
    end

    uploads = [ params[:primary_doc] ]
    uploads << params[:selfie] if @case.skip_persona?
    return unless uploaded_files_present?(uploads)

    # skip-persona cases are camera-capture only — the document AND a live
    # selfie, both JPEG/PNG straight from the camera widget, never an
    # arbitrary uploaded file
    if @case.skip_persona? && !uploads.all? { |f| f.content_type.to_s.match?(%r{\Aimage/(jpeg|png)\z}) }
      flash[:error] = "Your photos have to come straight from your camera"
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

      if @case.skip_persona?
        selfie = @case.documents.new(document_kind: "selfie", source: "direct_upload")
        selfie.file.attach(params[:selfie])
        selfie.save!
      end

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

  # call-capture disclosure must be acknowledged before the booking link shows
  def acknowledge_call_capture
    unless @case.booking_available?
      redirect_to manual_verification_path and return
    end

    @case.update!(call_capture_acknowledged: true)
    @case.log_event!(:call_capture_acknowledged, actor: current_identity, request: request)

    redirect_to manual_verification_path
  end

  private

  def set_case
    unless Flipper.enabled?(VerificationCase::FLIPPER_FLAG, current_identity)
      render(:link_invalid, status: :forbidden) and return if params[:token].present?
      redirect_to root_path and return
    end

    @case = current_identity.verification_cases.open_cases.order(created_at: :desc).first
    return if @case

    # someone followed an emailed link to a case that has since closed
    # (withdrawn, decided) — tell them, don't silently bounce to the home page
    if params[:token].present?
      render :link_invalid, status: :forbidden
    else
      redirect_to root_path
    end
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

  # shared by both submission paths: both checkboxes ticked and every
  # required field present. on failure, flashes + redirects and returns false.
  def submission_prerequisites_present?
    unless params[:attested] == "1" && params[:biometric_consent] == "1"
      flash[:error] = "Both the attestation and the consent checkbox are required"
      redirect_to manual_verification_path
      return false
    end

    missing = VerificationCase::REQUIRED_SUBMITTED_FIELDS.reject { |field| params[field].present? }
    if missing.any?
      flash[:error] = "#{missing.map(&:humanize).to_sentence} #{missing.one? ? "is" : "are"} required"
      redirect_to manual_verification_path
      return false
    end

    true
  end

  # every file param has to be an actual multipart upload with bytes in it.
  # a tampered form (or a browser posting a bare file field as text) sends a
  # string, which would otherwise blow up in attach. content type and size
  # limits are the Document model's job. on failure, flashes + redirects and
  # returns false.
  def uploaded_files_present?(uploads)
    unless uploads.all? { |upload| uploaded_file?(upload) }
      flash[:error] = "Please choose a file to upload"
      redirect_to manual_verification_path
      return false
    end

    if uploads.any? { |upload| upload.size.to_i.zero? }
      flash[:error] = "One of your files is empty — please choose it again"
      redirect_to manual_verification_path
      return false
    end

    true
  end

  def uploaded_file?(value)
    value.is_a?(ActionDispatch::Http::UploadedFile) ||
      %i[content_type original_filename tempfile size].all? { |m| value.respond_to?(m) }
  end
end
