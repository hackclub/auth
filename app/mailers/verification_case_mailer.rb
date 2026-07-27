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

  def call_cancelled(verification_case)
    @case = verification_case
    @identity = verification_case.identity
    @first_name = @identity.first_name
    @link = manual_verification_url
    @env_prefix = env_prefix
    @preview_text = "Your verification call was cancelled — pick a new time"

    mail(
      to: @identity.primary_email,
      subject: prefixed_subject("Your verification call was cancelled")
    )
  end
end
