class EmailChangeMailer < ApplicationMailer
  def verify_old_email(email_change_request)
    @email_change_request = email_change_request
    @identity = email_change_request.identity
    @first_name = @identity.first_name
    @token = email_change_request.old_email_token
    @new_email = email_change_request.new_email
    @verify_url = verify_old_email_change_url(token: @token)
    @cancel_url = cancel_email_change_url(id: email_change_request.id)
    @env_prefix = env_prefix

    mail(
      to: email_change_request.old_email,
      from: ACCOUNT_FROM,
      subject: prefixed_subject(t(".subject"))
    )
  end

  def verify_new_email(email_change_request)
    @email_change_request = email_change_request
    @identity = email_change_request.identity
    @first_name = @identity.first_name
    @token = email_change_request.new_email_token
    @old_email = email_change_request.old_email
    @verify_url = verify_new_email_change_url(token: @token)
    @env_prefix = env_prefix

    mail(
      to: email_change_request.new_email,
      from: ACCOUNT_FROM,
      subject: prefixed_subject(t(".subject"))
    )
  end

  def email_changed_notification(email_change_request)
    @email_change_request = email_change_request
    @identity = email_change_request.identity
    @first_name = @identity.first_name
    @old_email = email_change_request.old_email
    @new_email = email_change_request.new_email
    @env_prefix = env_prefix

    mail(
      to: [ email_change_request.old_email, email_change_request.new_email ],
      from: ACCOUNT_FROM,
      subject: prefixed_subject(t(".subject"))
    )
  end
end
