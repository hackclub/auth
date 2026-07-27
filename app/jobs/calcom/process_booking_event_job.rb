class Calcom::ProcessBookingEventJob < ApplicationJob
  queue_as :default

  def perform(event:, case_id:, booking_uid:, starts_at:)
    verification_case = VerificationCase.find_by(id: case_id)
    return unless verification_case

    case event
    when "BOOKING_CREATED", "BOOKING_RESCHEDULED"
      verification_case.update!(booking_uid: booking_uid, call_starts_at: starts_at&.to_time)
      verification_case.schedule_call! unless verification_case.call_scheduled?
      verification_case.log_event!(:call_booked, data: { event: event, booking_uid: booking_uid, starts_at: starts_at })
      VerificationCaseMailer.call_scheduled(verification_case).deliver_later
      Slack::VerificationCaseThreadJob.perform_later(verification_case, "call booked for #{starts_at}")
    when "BOOKING_CANCELLED"
      verification_case.update!(booking_uid: nil, call_starts_at: nil)
      verification_case.log_event!(:call_cancelled, data: { booking_uid: booking_uid })
      Slack::VerificationCaseThreadJob.perform_later(verification_case, "call cancelled — waiting on a rebook")
    end
  rescue AASM::InvalidTransition
    Rails.logger.info("[Calcom] Ignoring #{event} for case #{case_id} in state #{verification_case.status}")
  end
end
