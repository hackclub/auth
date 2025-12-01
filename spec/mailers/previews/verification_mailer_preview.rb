class VerificationMailerPreview < ActionMailer::Preview
  def approved
    verification = find_or_build_verification
    VerificationMailer.approved(verification)
  end

  def rejected_amicably
    verification = find_or_build_verification(rejected: true)
    VerificationMailer.rejected_amicably(verification)
  end

  def rejected_permanently
    verification = find_or_build_verification(rejected: true)
    VerificationMailer.rejected_permanently(verification)
  end

  def created
    verification = find_or_build_verification
    VerificationMailer.created(verification)
  end

  private

  def find_or_build_verification(rejected: false)
    if rejected
      existing = Verification::DocumentVerification.where.not(rejection_reason: nil).last
      return existing if existing
    else
      existing = Verification::DocumentVerification.last
      return existing if existing
    end

    identity = Identity.last || Identity.new(
      first_name: "Orpheus",
      primary_email: "orpheus@hackclub.com"
    )

    verification = Verification::DocumentVerification.new(identity: identity)
    if rejected
      verification.rejection_reason = "poor_quality"
      verification.rejection_reason_details = "Could not read the text"
    end
    verification
  end
end
