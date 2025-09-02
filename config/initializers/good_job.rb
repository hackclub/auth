Rails.application.configure do
  config.good_job.cron = {
    expire_draft_aadhaar_verifications: {
      cron: "*/5 * * * *", # Run every 5 minutes
      class: "Verification::ExpireDraftAadhaarVerificationsJob"
    }
  }
end
