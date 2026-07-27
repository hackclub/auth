module Webhooks
  # self-hosted cal.com webhooks the booking back into the case record.
  # signature: HMAC-SHA256 of the raw payload in X-Cal-Signature-256.
  class CalcomController < Webhooks::ApplicationController
    before_action :verify_signature!

    HANDLED_EVENTS = %w[BOOKING_CREATED BOOKING_RESCHEDULED BOOKING_CANCELLED BOOKING_NO_SHOW_UPDATED].freeze

    def create
      return head(:bad_request) unless parsed_body

      event = parsed_body[:triggerEvent]
      return head(:ok) unless HANDLED_EVENTS.include?(event)

      payload = parsed_body[:payload] || {}
      verification_case = find_case(payload)
      return head(:ok) unless verification_case

      Calcom::ProcessBookingEventJob.perform_later(
        event: event,
        case_id: verification_case.id,
        booking_uid: booking_uid(payload),
        starts_at: payload[:startTime],
        no_show: Array(payload[:attendees]).any? { |a| a[:noShow] }
      )

      head :ok
    end

    private

    # no-show payloads use bookingUid; booking payloads use uid
    def booking_uid(payload) = payload[:uid] || payload[:bookingUid]

    def find_case(payload)
      case_public_id = payload.dig(:metadata, :casePublicId)
      found = VerificationCase.find_by_public_id(case_public_id) if case_public_id.present?
      return found if found

      # no-show events carry no metadata — match the stored booking
      uid = booking_uid(payload)
      found = VerificationCase.open_cases.find_by(booking_uid: uid) if uid.present?
      return found if found

      # fallback: match on attendee email for bookings made without metadata
      emails = Array(payload[:attendees]).filter_map { |a| a[:email] }
      return nil if emails.empty?

      VerificationCase.open_cases.joins(:identity)
        .where(identities: { primary_email: emails })
        .order(created_at: :desc).first
    end

    def verify_signature!
      secret = ENV["CALCOM_WEBHOOK_SECRET"]
      return head(:service_unavailable) if secret.blank?

      signature = request.headers["X-Cal-Signature-256"]
      return head(:unauthorized) if signature.blank?

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, request.raw_post)
      unless ActiveSupport::SecurityUtils.secure_compare(signature, expected)
        Sentry.capture_message("Cal.com webhook signature mismatch",
          level: :warning, tags: { component: "calcom" }, extra: { ip: request.remote_ip })
        head(:unauthorized)
      end
    end

    def parsed_body
      return @parsed_body if defined?(@parsed_body)
      @parsed_body = JSON.parse(request.raw_post, symbolize_names: true)
    rescue JSON::ParserError
      @parsed_body = nil
    end
  end
end
