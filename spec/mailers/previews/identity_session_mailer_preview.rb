class IdentitySessionMailerPreview < ActionMailer::Preview
  def new_login
    session = IdentitySession.last || build_fake_session
    IdentitySessionMailer.new_login(session)
  end

  private

  def build_fake_identity
    Identity.new(
      first_name: "Orpheus",
      primary_email: "orpheus@hackclub.com"
    )
  end

  def build_fake_session
    identity = build_fake_identity
    IdentitySession.new(
      identity: identity,
      device_info: "Chrome 120",
      os_info: "macOS 14.2",
      ip: "198.51.100.42",
      latitude: 37.7749,
      longitude: -122.4194
    )
  end
end
