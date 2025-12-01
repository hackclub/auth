class VerificationMailer < ApplicationMailer
  default from: ApplicationMailer::IDENTITY_FROM

  def approved(verification)
    @verification = verification
    @identity = verification.identity
    @first_name = @identity.first_name
    @env_prefix = env_prefix
    @preview_text = "Your documents have been approved — you're all set!"

    mail(
      to: @identity.primary_email,
      subject: prefixed_subject(t(".subject"))
    )
  end

  def rejected_amicably(verification)
    @verification = verification
    @identity = verification.identity
    @first_name = @identity.first_name
    @reason_line = build_reason_line(verification)
    @resubmit_url = verification_step_url(:document)
    @env_prefix = env_prefix
    @preview_text = "We need you to resubmit your documents"

    mail(
      to: @identity.primary_email,
      subject: prefixed_subject(t(".subject"))
    )
  end

  def rejected_permanently(verification)
    @verification = verification
    @identity = verification.identity
    @first_name = @identity.first_name
    @reason_line = build_reason_line(verification)
    @env_prefix = env_prefix

    mail(
      to: @identity.primary_email,
      subject: prefixed_subject(t(".subject"))
    )
  end

  def created(verification)
    @verification = verification
    @identity = verification.identity
    @first_name = @identity.first_name
    @env_prefix = env_prefix
    @preview_text = "We got your documents and they're in the queue for review"

    mail(
      to: @identity.primary_email,
      subject: prefixed_subject(t(".subject"))
    )
  end

  private

  def build_reason_line(verification)
    reason = verification.try(:rejection_reason_name)&.downcase ||
             verification.rejection_reason&.humanize&.downcase ||
             "unknown issue"

    if verification.rejection_reason_details.present?
      reason += " (#{verification.rejection_reason_details})"
    end

    if verification.rejection_reason == "under_13"
      reason += ". You can resubmit once you turn 13"
    end

    reason
  end
end
