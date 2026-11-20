class VerificationCaseMailer < ApplicationMailer
  default from: ApplicationMailer::IDENTITY_FROM

  def invitation(verification_case, token)
    @case = verification_case
    @identity = verification_case.identity
    @first_name = @identity.first_name
    @link = manual_verification_url(token: token)
    @expires_at = verification_case.access_token_expires_at
    @env_prefix = env_prefix
    @preview_text = "Your manual verification link from Hack Club"

    mail(
      to: @identity.primary_email,
      subject: prefixed_subject("Your manual identity verification link")
    )
  end

  # nudge for a user who got the invitation but never started. carries a
  # fresh single-use link because the original may already be spent.
  def reminder(verification_case, token)
    @case = verification_case
    @identity = verification_case.identity
    @first_name = @identity.first_name
    @link = manual_verification_url(token: token)
    @expires_at = verification_case.access_token_expires_at
    @env_prefix = env_prefix
    @preview_text = "Your manual verification link is still waiting"

    mail(
      to: @identity.primary_email,
      subject: prefixed_subject("Reminder: your manual identity verification link")
    )
  end

  # deliberately reason-free: the rejection reason and its details are
  # internal reviewer notes, not something we relay to the user
  def denied(verification_case)
    @case = verification_case
    @identity = verification_case.identity
    @first_name = @identity.first_name
    @env_prefix = env_prefix
    @preview_text = "An update on your manual identity verification"

    mail(
      to: @identity.primary_email,
      subject: prefixed_subject("An update on your manual identity verification")
    )
  end

  # reviewer asked for the documents again — carries a fresh single-use link
  def redo_requested(verification_case, token, message)
    @case = verification_case
    @identity = verification_case.identity
    @first_name = @identity.first_name
    @message = message
    @link = manual_verification_url(token: token)
    @expires_at = verification_case.access_token_expires_at
    @env_prefix = env_prefix
    @preview_text = "We need you to resubmit your verification documents"

    mail(
      to: @identity.primary_email,
      subject: prefixed_subject("Please resubmit your verification documents")
    )
  end

  def call_scheduled(verification_case)
    @case = verification_case
    @identity = verification_case.identity
    @first_name = @identity.first_name
    @starts_at = verification_case.call_starts_at
    @env_prefix = env_prefix
    @preview_text = "Your verification call is booked"

    mail(
      to: @identity.primary_email,
      subject: prefixed_subject("Your verification call is booked")
    )
  end
end
