class Persona::ProcessInquiryEventJob < ApplicationJob
  queue_as :default

  def perform(event_name:, inquiry_id:)
    @verification = Verification::PersonaVerification.find_by!(persona_inquiry_id: inquiry_id)
    @identity = @verification.identity

    Sentry.set_tags(component: "persona", event: event_name)
    Sentry.set_extras(
      inquiry_id: inquiry_id,
      identity_id: @identity.id,
      identity_public_id: @identity.public_id,
      verification_id: @verification.id,
      verification_status: @verification.status,
      persona_account_id: @identity.persona_account_id
    )

    case event_name
    when "inquiry.completed"         then handle_completed(inquiry_id)
    when "inquiry.approved"          then handle_approved
    when "inquiry.declined"          then handle_declined(inquiry_id)
    when "inquiry.failed"            then handle_failed
    when "inquiry.expired"           then handle_expired
    when "inquiry.marked_for_review" then handle_marked_for_review
    end
  rescue AASM::InvalidTransition
    # idempotent: event already processed
    Rails.logger.info("[Persona] Ignoring duplicate #{event_name} for inquiry #{inquiry_id}")
  end

  private

  def handle_completed(inquiry_id)
    return if @verification.pending? || @verification.approved?

    inquiry = Persona.instance.retrieve_inquiry(inquiry_id)
    raise "no government ID verification found for inquiry #{inquiry_id}" unless inquiry.gov_id_verification_id

    save_inquiry_data(inquiry)

    @verification.mark_pending!
    @verification.create_activity(:persona_inquiry_completed, owner: @identity, recipient: @identity,
      parameters: { inquiry_id: inquiry_id })
  end

  def handle_approved
    return if @verification.approved?
    handle_completed(@verification.persona_inquiry_id) if @verification.draft?
    @verification.reload
    @verification.create_activity(:persona_inquiry_approved, recipient: @identity,
      parameters: { inquiry_id: @verification.persona_inquiry_id })
    Persona::VerificationPipelineJob.perform_later(@verification)
  end

  def handle_declined(inquiry_id)
    return if @verification.rejected?

    inquiry = Persona.instance.retrieve_inquiry(inquiry_id)

    begin
      save_inquiry_data(inquiry)
    rescue => e
      Sentry.capture_exception(e)
    end

    @verification.mark_as_rejected!(determine_decline_reason)
    @verification.create_activity(:persona_inquiry_declined, recipient: @identity,
      parameters: { inquiry_id: inquiry_id })
  end

  def handle_failed
    return if @verification.rejected?

    begin
      inquiry = Persona.instance.retrieve_inquiry(@verification.persona_inquiry_id)
      save_inquiry_data(inquiry)
    rescue => e
      Sentry.capture_exception(e)
    end

    @verification.mark_as_rejected!("too_many_attempts", "User exceeded the maximum number of verification attempts in Persona.")
    @verification.create_activity(:persona_inquiry_failed, recipient: @identity)
  end

  def handle_expired
    return if @verification.rejected?

    @verification.mark_as_rejected!("inquiry_expired", "The verification session expired before the user completed it.")
    @verification.create_activity(:persona_inquiry_expired, recipient: @identity)
  end

  def handle_marked_for_review
    @verification.create_activity(:persona_inquiry_marked_for_review,
      parameters: { inquiry_id: @verification.persona_inquiry_id })
  end

  # pull documents, photos, and extracted data from the inquiry and persist them.
  # nil-safe for gov_id — failed/declined inquiries may not have one.
  def save_inquiry_data(inquiry)
    service = Persona.instance

    gov_id = nil
    if (gov_id_ver_id = inquiry.gov_id_verification_id)
      gov_id = service.retrieve_government_id_verification(gov_id_ver_id)
    end

    photos = Persona::PhotoSet.empty
    inquiry.document_ids.each do |ref|
      photos += service.retrieve_document_photos(ref[:id], type: ref[:type])
    rescue Persona::APIError => e
      Sentry.capture_exception(e)
    end
    inquiry.verification_ids.each do |ref|
      photos += service.retrieve_verification_photos(ref[:id], type: ref[:type])
    rescue Persona::APIError => e
      Sentry.capture_exception(e)
    end

    gov_id_raw = gov_id ? gov_id.raw.except(:front_photo, :back_photo, :selfie_photo) : {}
    raw_response = {
      inquiry: inquiry.raw,
      government_id_verification: gov_id_raw,
      sessions: inquiry.sessions
    }

    ActiveRecord::Base.transaction do
      record = Identity::PersonaRecord.find_or_create_by!(inquiry_id: inquiry.id) do |r|
        r.identity = @identity
        r.raw_json_response = raw_response.to_json
        r.name_first = gov_id&.name_first
        r.name_last = gov_id&.name_last
        r.birthdate = gov_id&.birthdate
        r.country_code = gov_id&.country_code || @identity.country
        r.persona_status = inquiry.status
        r.id_class = gov_id&.id_class
        r.expiration_date = gov_id&.expiration_date
        r.entity_confidence_score = gov_id&.entity_confidence_score
        r.checks = gov_id&.checks
        r.behaviors = inquiry.behaviors
        r.network_signals = build_network_signals(inquiry.sessions)
      end

      unless @verification.identity_document.present?
        all_photos = photos.document + photos.liveness
        doc = create_document(:persona_gov_id, all_photos)
        @verification.update!(persona_record: record, identity_document: doc)
      end

      @identity.update!(persona_account_id: inquiry.account_id) if @identity.persona_account_id.blank?
    end
  end

  def create_document(type, photo_array)
    return nil if photo_array.blank?

    doc = Identity::Document.new(identity: @identity, document_type: type)
    photo_array.each_with_index do |photo, i|
      attach_photo(doc, photo, photo[:label] || photo[:filename] || "photo_#{i + 1}")
    end

    return nil unless doc.files.any?
    doc.save!
    doc
  end

  def attach_photo(doc, photo_data, label)
    return unless photo_data.is_a?(Hash) && photo_data[:url]

    raw = Persona.instance.download_file(photo_data[:url])
    bytes = raw.respond_to?(:read) ? raw.read : raw
    filename = photo_data[:filename] || "#{label}.jpg"

    doc.files.attach(
      io: StringIO.new(bytes),
      filename: filename,
      content_type: "image/jpeg"
    )
  rescue Persona::APIError => e
    Sentry.capture_exception(e)
  end

  def build_network_signals(sessions)
    s = sessions&.first || {}
    {
      is_tor: s[:is_tor],
      is_proxy: s[:is_proxy],
      is_vpn: s[:is_vpn],
      is_datacenter: s[:is_datacenter],
      threat_level: s[:threat_level],
      country_code: s[:country_code],
      ip_isp: s[:ip_isp],
      device_type: s[:device_type]
    }.compact
  end

  def determine_decline_reason
    checks = @verification.persona_record&.checks
    return "other" if checks.blank?

    failed = checks.select { |c| c["status"] == "failed" && c["requirement"] == "required" }
    return "other" if failed.empty?

    names = failed.map { |c| c["name"] }

    if names.include?("id_expired_detection")
      "expired"
    else
      "poor_quality"
    end
  end
end
