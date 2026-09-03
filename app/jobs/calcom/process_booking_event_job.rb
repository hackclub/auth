class Calcom::ProcessBookingEventJob < ApplicationJob
  queue_as :default

  def perform(event:, case_id:, booking_uid:, starts_at:, no_show: false)
    verification_case = VerificationCase.find_by(id: case_id)
    return unless verification_case

    case event
    when "BOOKING_CREATED", "BOOKING_RESCHEDULED"
      verification_case.update!(booking_uid: booking_uid, call_starts_at: starts_at&.to_time)
      verification_case.schedule_call! unless verification_case.call_scheduled?
      verification_case.log_event!(:call_booked, data: { event: event, booking_uid: booking_uid, starts_at: starts_at })
      VerificationCaseMailer.call_scheduled(verification_case).deliver_later
    when "BOOKING_CANCELLED"
      # cal.com emails the attendee about the cancellation (with a rebook
      # link) — we only put the case back so our status page stays truthful
      verification_case.unschedule_call! if verification_case.call_scheduled?
      verification_case.update!(booking_uid: nil, call_starts_at: nil)
      verification_case.log_event!(:call_cancelled, data: { booking_uid: booking_uid })
    when "BOOKING_NO_SHOW_UPDATED"
      # only when the host MARKS a no-show — un-marking changes nothing here.
      # the booking is spent, so the case reopens for booking like a
      # cancellation, and the audit trail makes repeat no-shows visible
      # (staff can deny with the existing no_show rejection reason).
      return unless no_show

      verification_case.unschedule_call! if verification_case.call_scheduled?
      verification_case.update!(booking_uid: nil, call_starts_at: nil)
      verification_case.log_event!(:call_no_show, data: { booking_uid: booking_uid })
    end
  rescue AASM::InvalidTransition
    Rails.logger.info("[Calcom] Ignoring #{event} for case #{case_id} in state #{verification_case.status}")
  end
end
