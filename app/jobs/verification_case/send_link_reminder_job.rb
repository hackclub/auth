# daily nudge for cases where the invitation went out but the user never
# started. one reminder per case, ever — the audit trail is the record of
# whether it was sent, so there's no extra column to keep in sync.
class VerificationCase::SendLinkReminderJob < ApplicationJob
  queue_as :default

  QUIET_FOR = 3.days

  def perform
    VerificationCase.due_for_link_reminder(quiet_for: QUIET_FOR).find_each do |verification_case|
      token = verification_case.rotate_access_link!
      VerificationCaseMailer.reminder(verification_case, token).deliver_later
      verification_case.log_event!(:reminder_sent)
    end
  end
end
