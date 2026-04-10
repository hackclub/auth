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
    when "inquiry.completed"  then handle_completed(inquiry_id)
    when "inquiry.approved"   then handle_approved
    when "inquiry.declined"   then handle_declined(inquiry_id)
    when "inquiry.marked_for_review" then nil # no state change
    end
  rescue AASM::InvalidTransition
    # idempotent: event already processed
    Rails.logger.info("[Persona] Ignoring duplicate #{event_name} for inquiry #{inquiry_id}")
  end

  private

  def handle_completed(inquiry_id)
    return if @verification.persona_record.present? # idempotent guard

    service = Persona.instance
    inquiry = service.retrieve_inquiry(inquiry_id)

    gov_id_ver_id = inquiry.gov_id_verification_id
    raise "no government ID verification found for inquiry #{inquiry_id}" unless gov_id_ver_id

    gov_id = service.retrieve_government_id_verification(gov_id_ver_id)

    # create the persona record
    record = Identity::PersonaRecord.create!(
      identity: @identity,
      inquiry_id: inquiry_id,
      raw_json_response: inquiry.to_h.to_json,
      name_first: gov_id.name_first,
      name_last: gov_id.name_last,
      birthdate: gov_id.birthdate,
      country_code: gov_id.country_code,
      persona_status: inquiry.status
    )

    # create the gov ID document with front/back photos
    doc = Identity::Document.new(
      identity: @identity,
      document_type: :persona_gov_id
    )
    attach_photo(doc, gov_id.front_photo, "front")
    attach_photo(doc, gov_id.back_photo, "back")
    doc.save!

    # link everything to the verification
    @verification.update!(persona_record: record, identity_document: doc)

    # store account ID on identity if not set
    @identity.update!(persona_account_id: inquiry.account_id) if @identity.persona_account_id.blank?

    @verification.mark_pending!
  end

  def handle_approved
    return if @verification.approved? # idempotent guard

    @verification.approve!
  end

  def handle_declined(inquiry_id)
    return if @verification.rejected? # idempotent guard

    inquiry = Persona.instance.retrieve_inquiry(inquiry_id)
    reason = map_decline_reason(inquiry.status)

    @verification.mark_as_rejected!(reason)
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
