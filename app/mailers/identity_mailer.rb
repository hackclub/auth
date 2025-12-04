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
