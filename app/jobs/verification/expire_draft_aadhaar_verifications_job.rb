class Verification::ExpireDraftAadhaarVerificationsJob < ApplicationJob
  def perform
    expired_verifications = Verification::AadhaarVerification
      .where(status: "draft")
      .where("created_at < ?", 10.minutes.ago)

    expired_count = 0

    expired_verifications.find_each do |verification|
      verification.mark_as_rejected!("service_unavailable", "Verification expired after 10 minutes")
      expired_count += 1
    end

    Rails.logger.info "Expired #{expired_count} draft Aadhaar verifications"
  end
end
