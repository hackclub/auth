class Calcom::ProcessBookingEventJob < ApplicationJob
  queue_as :default

  # which case states each cal.com event may touch. checked under the row
  # lock BEFORE any write, so a booking that lands on a withdrawn / held /
  # decided case leaves it exactly as it was (plus an audit row saying so).
  BOOKING_EVENTS = %w[BOOKING_CREATED BOOKING_RESCHEDULED].freeze
  RELEASE_EVENTS = %w[BOOKING_CANCELLED BOOKING_NO_SHOW_UPDATED].freeze

  ALLOWED_STATES = {
    "BOOKING_CREATED" => %w[docs_submitted call_scheduled],
    "BOOKING_RESCHEDULED" => %w[docs_submitted call_scheduled],
    "BOOKING_CANCELLED" => %w[call_scheduled],
    "BOOKING_NO_SHOW_UPDATED" => %w[call_scheduled]
  }.freeze

  def perform(event:, case_id:, booking_uid:, starts_at:, no_show: false)
    verification_case = VerificationCase.find_by(id: case_id)
    return unless verification_case

    # only when the host MARKS a no-show — un-marking changes nothing here.
    return if event == "BOOKING_NO_SHOW_UPDATED" && !no_show

    # the mail goes out after the lock is released and the transaction has
    # committed, so a rollback can never leave a "your call is booked" email
    # behind, and a retry of this job sees the committed booking (dedup below).
    outcome = verification_case.with_lock do
      next :ignored unless state_allowed?(verification_case, event, booking_uid)

      case event
      when *BOOKING_EVENTS then book!(verification_case, event, booking_uid, starts_at)
      when *RELEASE_EVENTS then release!(verification_case, event, booking_uid)
      end
    end

    VerificationCaseMailer.call_scheduled(verification_case).deliver_later if outcome == :booked
  rescue AASM::InvalidTransition
    # the state check above should make this unreachable; kept so a racing
    # transition between our check and the aasm guard can't crash the job.
    Rails.logger.info("[Calcom] Ignoring #{event} for case #{case_id} in state #{verification_case.status}")
  end

  private

  # false (after writing a non-destructive audit row) when the case isn't in
  # a state this event may act on, or when a cancellation/no-show refers to
  # a booking other than the one currently on the case (a stale uid must not
  # knock a newer booking off).
  def state_allowed?(verification_case, event, booking_uid)
    reason =
      if !ALLOWED_STATES.fetch(event, []).include?(verification_case.status)
        "state_#{verification_case.status}"
      elsif RELEASE_EVENTS.include?(event) && stale_booking?(verification_case, booking_uid)
        "stale_booking_uid"
      end
    return true unless reason

    Rails.logger.info("[Calcom] Ignoring #{event} for case #{verification_case.id} (#{reason})")
    verification_case.log_event!(:call_booking_ignored,
      data: { event: event, booking_uid: booking_uid, status: verification_case.status, reason: reason })
    false
  end

  def stale_booking?(verification_case, booking_uid)
    booking_uid.present? && verification_case.booking_uid.present? && verification_case.booking_uid != booking_uid
  end

  # returns :booked when the booking changed (fields written, event logged,
  # mail due), :duplicate when cal.com re-delivered what we already hold.
  def book!(verification_case, event, booking_uid, starts_at)
    new_starts_at = starts_at&.to_time

    if verification_case.call_scheduled? && same_booking?(verification_case, booking_uid, new_starts_at)
      Rails.logger.info("[Calcom] Ignoring duplicate #{event} for case #{verification_case.id}")
      return :duplicate
    end

    verification_case.assign_attributes(booking_uid: booking_uid, call_starts_at: new_starts_at)
    # schedule_call self-transitions from call_scheduled, so a genuine
    # reschedule and a first booking share one path; aasm saves the record
    # (and the booking fields with it) as part of the transition.
    verification_case.schedule_call!
    verification_case.log_event!(:call_booked, data: { event: event, booking_uid: booking_uid, starts_at: starts_at })
    :booked
  end

  def same_booking?(verification_case, booking_uid, new_starts_at)
    verification_case.booking_uid == booking_uid &&
      verification_case.call_starts_at&.to_i == new_starts_at&.to_i
  end

  # cal.com emails the attendee about a cancellation (with a rebook link) —
  # we only put the case back so our status page stays truthful. a no-show
  # spends the booking the same way, and the audit trail makes repeat
  # no-shows visible (staff can deny with the existing no_show reason).
  def release!(verification_case, event, booking_uid)
    verification_case.assign_attributes(booking_uid: nil, call_starts_at: nil)
    verification_case.unschedule_call!
    key = event == "BOOKING_CANCELLED" ? :call_cancelled : :call_no_show
    verification_case.log_event!(key, data: { booking_uid: booking_uid })
    :released
  end
end
