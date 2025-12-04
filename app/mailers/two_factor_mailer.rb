class TwoFactorMailer < ApplicationMailer
  def authentication_method_enabled(identity)
    @identity = identity
    @first_name = identity.first_name
    @env_prefix = env_prefix

    mail(
      to: identity.primary_email,
      from: ACCOUNT_FROM,
      subject: prefixed_subject(t(".subject"))
    )
  end

  def authentication_method_disabled(identity)
    @identity = identity
    @first_name = identity.first_name
    @env_prefix = env_prefix

    mail(
      to: identity.primary_email,
      from: ACCOUNT_FROM,
      subject: prefixed_subject(t(".subject"))
    )
  end

  def required_authentication_enabled(identity)
    @identity = identity
    @first_name = identity.first_name
    @env_prefix = env_prefix

    mail(
      to: identity.primary_email,
      from: ACCOUNT_FROM,
      subject: prefixed_subject(t(".subject"))
    )
  end

  def required_authentication_disabled(identity)
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
