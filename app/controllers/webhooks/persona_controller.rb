module Webhooks
  class PersonaController < Webhooks::ApplicationController
    TIMESTAMP_TOLERANCE = 5.minutes

    before_action :verify_signature!

    def create
      event_name = parsed_body.dig("data", "attributes", "name")
      inquiry_id = parsed_body.dig("data", "attributes", "payload", "data", "id")

      Persona::ProcessInquiryEventJob.perform_later(
        event_name: event_name,
        inquiry_id: inquiry_id
      )

      head :ok
    end

    private

    def verify_signature!
      signature_header = request.headers["Persona-Signature"]
      return head(:unauthorized) if signature_header.blank?

      parts = signature_header.split(",")
      timestamp = parts.find { |p| p.start_with?("t=") }&.delete_prefix("t=")
      signatures = parts.select { |p| p.start_with?("v1=") }.map { |p| p.delete_prefix("v1=") }

      return head(:unauthorized) if timestamp.blank? || signatures.empty?
      return head(:unauthorized) if Time.at(timestamp.to_i) < TIMESTAMP_TOLERANCE.ago

      expected = OpenSSL::HMAC.hexdigest(
        "SHA256",
        webhook_secret,
        "#{timestamp}.#{request.raw_post}"
      )

      unless signatures.any? { |sig| ActiveSupport::SecurityUtils.secure_compare(sig, expected) }
        return head(:unauthorized)
      end
    end

    def parsed_body
      @parsed_body ||= JSON.parse(request.raw_post)
    rescue JSON::ParserError
      head(:bad_request) and return
    end

    def webhook_secret
      Rails.application.credentials.persona.webhook_secret
    end
  end
end
