# daily nudge for cases where the invitation went out but the user never
# opened it. one reminder per case, ever — the audit trail is the record of
# whether it was sent, so there's no extra column to keep in sync.
class VerificationCase::SendLinkReminderJob < ApplicationJob
  queue_as :default

  QUIET_FOR = 3.days

  def perform
    VerificationCase.due_for_link_reminder(quiet_for: QUIET_FOR).find_each do |verification_case|
      # the scope already excludes opened links, but the user may click
      # theirs between our query and this iteration — re-check under the
      # row lock so we never rotate a link out from under a live session
      token = verification_case.with_lock do
        verification_case.access_token_used_at.nil? ? verification_case.rotate_access_link! : nil
      end
      next if token.nil?

      VerificationCaseMailer.reminder(verification_case, token).deliver_later
      verification_case.log_event!(:reminder_sent)
    end
  end
end
