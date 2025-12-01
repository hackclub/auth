class IdentityMailer < ApplicationMailer
  def v2_login_code(login_code)
    @login_code = login_code
    @identity = login_code.identity
    @first_name = @identity.first_name
    @code = login_code.pretty
    @env_prefix = env_prefix
    @preview_text = "Your code is #{@code}"

    mail(
      to: @identity.primary_email,
      from: ACCOUNT_FROM,
      subject: prefixed_subject(t(".subject", code: @code))
    )
  end

  def step_up_code(identity, login_code)
    # Reuse the same transactional email template as v2_login_code
    # The message context is similar - verifying identity via email code
    @TRANSACTIONAL_ID = "cmgqzc6351kcqzv0i8yrwl1nt"

    @login_code = login_code
    @recipient = identity.primary_email

    @datavariables = {
      code: login_code.pretty,
      first_name: identity.first_name
    }

    send_it!
  end

  def approved_but_ysws_ineligible(identity)
    @identity = identity
    @first_name = identity.first_name
    @env_prefix = env_prefix

    mail(
      to: identity.primary_email,
      from: IDENTITY_FROM,
      subject: prefixed_subject(t(".subject"))
    )
  end
end
