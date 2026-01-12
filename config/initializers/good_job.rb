Rails.application.configure do
  config.good_job.cron = {
    expire_draft_aadhaar_verifications: {
      cron: "*/5 * * * *", # Run every 5 minutes
      class: "Verification::ExpireDraftAadhaarVerificationsJob"
    },
    purge_old_analytics: {
      cron: "0 4 * * *", # Run daily at 4am
      class: "Analytics::PurgeOldDataJob"
    }
  }
  config.good_job.enable_cron = true
end
