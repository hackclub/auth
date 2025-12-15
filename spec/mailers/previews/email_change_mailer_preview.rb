class EmailChangeMailerPreview < ActionMailer::Preview
  def verify_old_email
    EmailChangeMailer.verify_old_email(email_change_request)
  end

  def verify_new_email
    EmailChangeMailer.verify_new_email(email_change_request)
  end

  def email_changed_notification
    request = email_change_request
    request.completed_at = Time.current
    EmailChangeMailer.email_changed_notification(request)
  end

  private

  def email_change_request
    identity = Identity.last || build_fake_identity

    request = identity.email_change_requests.first
    return request if request

    Identity::EmailChangeRequest.new(
      id: 1,
      identity: identity,
      old_email: identity.primary_email,
      new_email: "newemail@example.com",
      old_email_token: SecureRandom.urlsafe_base64(32),
      new_email_token: SecureRandom.urlsafe_base64(32),
      expires_at: 24.hours.from_now
    )
  end

  def build_fake_identity
    Identity.new(
      id: 1,
      first_name: "Orpheus",
      last_name: "Mascot",
      primary_email: "orpheus@hackclub.com"
    )
  end
end
