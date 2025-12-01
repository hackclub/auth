class TOTPMailer < ApplicationMailer
  def enabled(identity)
    @identity = identity
    @first_name = identity.first_name
    @env_prefix = env_prefix

    mail(
      to: identity.primary_email,
      from: ACCOUNT_FROM,
      subject: prefixed_subject(t(".subject"))
    )
  end

  def disabled(identity)
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
