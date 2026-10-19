module Webhooks
  class PersonaController < Webhooks::ApplicationController
    TIMESTAMP_TOLERANCE = 5.minutes

    before_action :verify_signature!

    HANDLED_EVENTS = %w[
      inquiry.completed inquiry.approved inquiry.declined
      inquiry.failed inquiry.expired inquiry.marked_for_review
    ].freeze

    def create
      return head(:bad_request) unless parsed_body

      event_name = parsed_body.dig(:data, :attributes, :name)
      inquiry_id = parsed_body.dig(:data, :attributes, :payload, :data, :id)

      return head(:bad_request) if event_name.blank? || inquiry_id.blank?
      return link_staff_inquiry(inquiry_id) if event_name == "inquiry.created"
      return head(:ok) unless HANDLED_EVENTS.include?(event_name)

      Persona::ProcessInquiryEventJob.perform_later(
        event_name: event_name,
        inquiry_id: inquiry_id
      )

      head :ok
    end

    private

    # inquiries we create through the API have creator "API"; anything else is
    # the email of whoever made it by hand in the persona dashboard — see
    # LinkStaffInquiryJob
    def link_staff_inquiry(inquiry_id)
      attributes = parsed_body.dig(:data, :attributes, :payload, :data, :attributes) || {}
      creator = attributes[:creator]
      reference_id = attributes[:"reference-id"]

      if creator.present? && creator != "API" && reference_id.present?
        Persona::LinkStaffInquiryJob.perform_later(
          inquiry_id: inquiry_id,
          creator: creator,
          reference_id: reference_id
        )
      end

      head :ok
    end

    def verify_signature!
      signature_header = request.headers["Persona-Signature"]
      return head(:unauthorized) if signature_header.blank?

      parts = signature_header.split(",")
      timestamp = parts.find { |p| p.start_with?("t=") }&.delete_prefix("t=")
      signatures = parts.select { |p| p.start_with?("v1=") }.map { |p| p.delete_prefix("v1=") }

      return head(:unauthorized) if timestamp.blank? || signatures.empty?
      received_at = Time.at(timestamp.to_i)
      return head(:unauthorized) if received_at < TIMESTAMP_TOLERANCE.ago || received_at > TIMESTAMP_TOLERANCE.from_now

      expected = OpenSSL::HMAC.hexdigest(
        "SHA256",
        webhook_secret,
        "#{timestamp}.#{request.raw_post}"
      )

      unless signatures.any? { |sig| ActiveSupport::SecurityUtils.secure_compare(sig, expected) }
        Sentry.capture_message("Persona webhook signature mismatch",
          level: :warning,
          tags: { component: "persona" },
          extra: { timestamp: timestamp, ip: request.remote_ip })
        head(:unauthorized)
      end
    end

    def parsed_body
      return @parsed_body if defined?(@parsed_body)
      @parsed_body = JSON.parse(request.raw_post, symbolize_names: true)
    rescue JSON::ParserError
      @parsed_body = nil
    end

    def webhook_secret = Rails.application.credentials.persona.webhook_secret
  end
end
