class IdentityMailer < ApplicationMailer
  def v2_login_code(login_code)
    @TRANSACTIONAL_ID = "cmgqzc6351kcqzv0i8yrwl1nt"

    @login_code = login_code
    identity = login_code.identity
    @recipient = identity.primary_email

    @datavariables = {
      code: login_code.pretty,
      first_name: identity.first_name
    }

    send_it!
  end
  def login_code(login_code)
    @TRANSACTIONAL_ID = "cmbgs1y0p0c872j0in3n3knjj"

    @login_code = login_code
    identity = login_code.identity
    @recipient = identity.primary_email

    @datavariables = {
      login_url: verify_sessions_url(token: login_code.token),
      first_name: identity.first_name
    }

    send_it!
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
    @TRANSACTIONAL_ID = "cmbyoymlh0qfpy10i8ixgxj9d"

    @identity = identity
    @recipient = identity.primary_email

    @datavariables = {
      first_name: identity.first_name
    }

    send_it!
  end
end
