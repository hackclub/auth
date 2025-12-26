Rails.application.configure do
  config.good_job.cron = {
    expire_draft_aadhaar_verifications: {
      cron: "*/5 * * * *", # Run every 5 minutes
      class: "Verification::ExpireDraftAadhaarVerificationsJob"
    },
    rails_pulse_summary: {
      cron: "5 * * * *", # Run 5 minutes past every hour
      class: "RailsPulse::SummaryJob"
    },
    rails_pulse_cleanup: {
      cron: "0 1 * * *", # Run daily at 1:00 AM
      class: "RailsPulse::CleanupJob"
    }
  }
  config.good_job.enable_cron = true
end
