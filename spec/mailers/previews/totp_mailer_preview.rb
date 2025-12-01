class TOTPMailerPreview < ActionMailer::Preview
  def enabled
    identity = Identity.last || build_fake_identity
    TOTPMailer.enabled(identity)
  end

  def disabled
    identity = Identity.last || build_fake_identity
    TOTPMailer.disabled(identity)
  end

  private

  def build_fake_identity
    Identity.new(
      first_name: "Orpheus",
      primary_email: "orpheus@hackclub.com"
    )
  end
end
