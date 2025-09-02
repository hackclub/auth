class VerificationMailer < ApplicationMailer
  def approved(verification)
    @TRANSACTIONAL_ID = "cmbgujk6r05rpwu0ip60klxna"

    @verification = verification
    @identity = verification.identity
    @recipient = @identity.primary_email

    @datavariables = {
      first_name: @identity.first_name
    }

    send_it!
  end

  def rejected_amicably(verification)
    @TRANSACTIONAL_ID = "cmbguquvi07mowh0idvygxnia"

    @verification = verification
    @identity = verification.identity
    @recipient = @identity.primary_email

    reason_line = @verification.try(:rejection_reason_name)&.downcase || @verification.rejection_reason.humanize.downcase
    reason_line += " (#{@verification.rejection_reason_details})" if @verification.rejection_reason_details.present?

    if @verification.rejection_reason == "under_11"
      reason_line += ". You can resubmit your application once you turn 11 years old"
    end

    @datavariables = {
      first_name: @identity.first_name,
      reason_line:,
      resubmit_url: document_onboarding_url
    }

    send_it!
  end

  def rejected_permanently(verification)
    @TRANSACTIONAL_ID = "cmbgv0dcb03s5zx0ieso1prer"

    @verification = verification
    @identity = verification.identity
    @recipient = @identity.primary_email

    reason_line = @verification.try(:rejection_reason_name)&.downcase || @verification.rejection_reason.humanize.downcase
    reason_line += " (#{@verification.rejection_reason_details})" if @verification.rejection_reason_details.present?

    @datavariables = {
      first_name: @identity.first_name,
      reason_line:
    }

    send_it!
  end

  def created(verification)
    @TRANSACTIONAL_ID = "cmbiea17f0agt5p0i9ry4ca0n"

    @verification = verification
    @identity = verification.identity
    @recipient = @identity.primary_email

    @datavariables = {
      first_name: @identity.first_name
    }

    send_it!
  end
end
