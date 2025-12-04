class TwoFactorMailerPreview < ActionMailer::Preview
  def authentication_method_enabled
    identity = Identity.last || build_fake_identity
    TwoFactorMailer.authentication_method_enabled(identity)
  end

  def authentication_method_disabled
    identity = Identity.last || build_fake_identity
    TwoFactorMailer.authentication_method_disabled(identity)
  end

  def required_authentication_enabled
    identity = Identity.last || build_fake_identity
    TwoFactorMailer.required_authentication_enabled(identity)
  end

  def required_authentication_disabled
    identity = Identity.last || build_fake_identity
    TwoFactorMailer.required_authentication_disabled(identity)
  end

  private

  def build_fake_identity
    Identity.new(
      first_name: "Orpheus",
      primary_email: "orpheus@hackclub.com"
    )
  end
end
