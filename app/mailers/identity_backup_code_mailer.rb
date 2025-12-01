class IdentityBackupCodeMailer < ApplicationMailer
  def code_used(identity)
    @identity = identity
    @first_name = identity.first_name
    @env_prefix = env_prefix

    mail(
      to: identity.primary_email,
      from: ACCOUNT_FROM,
      subject: prefixed_subject(t(".subject"))
    )
  end

  def codes_regenerated(identity)
    @identity = identity
    @first_name = identity.first_name
    @env_prefix = env_prefix

    mail(
      to: identity.primary_email,
      from: ACCOUNT_FROM,
      subject: prefixed_subject(t(".subject"))
    )
  end
end
