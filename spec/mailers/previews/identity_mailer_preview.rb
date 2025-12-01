class IdentityMailerPreview < ActionMailer::Preview
  def v2_login_code
    login_code = Identity::V2LoginCode.last || build_fake_login_code
    IdentityMailer.v2_login_code(login_code)
  end

  def approved_but_ysws_ineligible
    identity = Identity.last || build_fake_identity
    IdentityMailer.approved_but_ysws_ineligible(identity)
  end

  private

  def build_fake_identity
    Identity.new(
      first_name: "Orpheus",
      primary_email: "orpheus@hackclub.com"
    )
  end

  def build_fake_login_code
    identity = build_fake_identity
    Identity::VLoginCode.new(
      identity: identity,
      token: "420069",
    )
  end
end
