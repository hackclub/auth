class VerificationCaseMailerPreview < ActionMailer::Preview
  def invitation
    VerificationCaseMailer.invitation(build_case, "preview-token")
  end

  def reminder
    VerificationCaseMailer.reminder(build_case, "preview-token")
  end

  def call_scheduled
    VerificationCaseMailer.call_scheduled(build_case(call_starts_at: 2.days.from_now))
  end

  def denied
    VerificationCaseMailer.denied(build_case)
  end

  private

  def build_case(**attrs)
    identity = Identity.last || Identity.new(first_name: "Orpheus", primary_email: "orpheus@example.com")
    VerificationCase.new(identity: identity, access_token_expires_at: 7.days.from_now, **attrs)
  end
end
