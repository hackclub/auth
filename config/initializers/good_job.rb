Rails.application.configure do
  config.good_job.cron = {
    # expire_draft_aadhaar_verifications: {
    #   cron: "*/5 * * * *", # Run every 5 minutes
    #   class: "Verification::ExpireDraftAadhaarVerificationsJob"
    # },
    purge_old_analytics: {
      cron: "0 4 * * *", # Run daily at 4am
      class: "Analytics::PurgeOldDataJob"
    },
    reap_aged_out_users: {
      cron: "0 3 * * *", # Run daily at 3am
      class: "Identity::ReapAgedOutUsersJob"
    },
    purge_expired_case_documents: {
      cron: "30 4 * * *", # Run daily at 4:30am
      class: "VerificationCases::PurgeExpiredDocumentsJob"
    }
  }
  config.good_job.enable_cron = true
end
