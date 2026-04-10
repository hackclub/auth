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
    when "inquiry.marked_for_review" then nil # no state change
    end
  rescue AASM::InvalidTransition
    # idempotent: event already processed
    Rails.logger.info("[Persona] Ignoring duplicate #{event_name} for inquiry #{inquiry_id}")
  end

  private

  def handle_completed(inquiry_id)
    return if @verification.pending? || @verification.approved? # idempotent guard

    service = Persona.instance
    inquiry = service.retrieve_inquiry(inquiry_id)

    gov_id_ver_id = inquiry.gov_id_verification_id
    raise "no government ID verification found for inquiry #{inquiry_id}" unless gov_id_ver_id

    gov_id = service.retrieve_government_id_verification(gov_id_ver_id)

    # collect photos from all documents + verifications on the inquiry
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

    # store full response for audit trail — strip photo URLs (images stored in Identity::Document)
    gov_id_hash = gov_id.to_h.except(:front_photo, :back_photo, :selfie_photo)
    raw_response = { inquiry: inquiry.to_h, government_id_verification: gov_id_hash }

    ActiveRecord::Base.transaction do
      record = Identity::PersonaRecord.find_or_create_by!(inquiry_id: inquiry_id) do |r|
        r.identity = @identity
        r.raw_json_response = raw_response.to_json
        r.name_first = gov_id.name_first
        r.name_last = gov_id.name_last
        r.birthdate = gov_id.birthdate
        r.country_code = gov_id.country_code || @identity.country
        r.persona_status = inquiry.status
        r.id_class = gov_id.id_class
        r.expiration_date = gov_id.expiration_date
        r.entity_confidence_score = gov_id.entity_confidence_score
        r.checks = gov_id.checks
      end

      unless @verification.identity_document.present?
        all_photos = photos.document + photos.liveness
        doc = create_document(:persona_gov_id, all_photos)
        @verification.update!(persona_record: record, identity_document: doc)
      end

      # store account ID on identity if not set
      @identity.update!(persona_account_id: inquiry.account_id) if @identity.persona_account_id.blank?

      @verification.mark_pending!
      @identity.create_activity(:persona_inquiry_completed, owner: @identity, recipient: @identity,
        parameters: { inquiry_id: inquiry_id, verification_id: @verification.id })
    end
  end

  def handle_approved
    return if @verification.approved?
    handle_completed(@verification.persona_inquiry_id) if @verification.draft?
    @verification.reload
    @verification.approve!
    @identity.create_activity(:persona_inquiry_approved, owner: @identity, recipient: @identity,
      parameters: { inquiry_id: @verification.persona_inquiry_id, verification_id: @verification.id })
  end

  def handle_declined(inquiry_id)
    return if @verification.rejected? # idempotent guard

    inquiry = Persona.instance.retrieve_inquiry(inquiry_id)
    reason = map_decline_reason(inquiry.status)

    @verification.mark_as_rejected!(reason)
    @identity.create_activity(:persona_inquiry_declined, owner: @identity, recipient: @identity,
      parameters: { inquiry_id: inquiry_id, verification_id: @verification.id })
  end

  def handle_failed
    return if @verification.rejected?

    @verification.mark_as_rejected!("too_many_attempts", "User exceeded the maximum number of verification attempts in Persona.")
    @identity.create_activity(:persona_inquiry_failed, owner: @identity, recipient: @identity,
      parameters: { verification_id: @verification.id })
  end

  def handle_expired
    return if @verification.rejected?

    @verification.mark_as_rejected!("inquiry_expired", "The verification session expired before the user completed it.")
    @identity.create_activity(:persona_inquiry_expired, owner: @identity, recipient: @identity,
      parameters: { verification_id: @verification.id })
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
  end

  def map_decline_reason(status)
    # map Persona's decline reasons to our rejection reasons
    # Persona doesn't give granular decline reasons on the inquiry level,
    # so we default to info_mismatch
    "info_mismatch"
  end
end
