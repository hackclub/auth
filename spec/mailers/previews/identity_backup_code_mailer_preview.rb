class IdentityBackupCodeMailerPreview < ActionMailer::Preview
  def code_used
    identity = Identity.last || build_fake_identity
    IdentityBackupCodeMailer.code_used(identity)
  end

  def codes_regenerated
    identity = Identity.last || build_fake_identity
    IdentityBackupCodeMailer.codes_regenerated(identity)
  end

  private

  def build_fake_identity
    Identity.new(
      first_name: "Orpheus",
      primary_email: "orpheus@hackclub.com"
    )
  end
end
