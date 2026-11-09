# frozen_string_literal: true

module Directory
  class RevokeSessionJob < ApplicationJob
    include GoodJob::ActiveJobExtensions::Concurrency

    queue_as :default

    class RevocationFailed < StandardError; end

    # Cloudflare's API allows ~1200 requests per 5 minutes per token; stay under it per
    # account. Throttled jobs are rescheduled by GoodJob, not counted as failures.
    good_job_control_concurrency_with(
      perform_throttle: [ 1000, 5.minutes ],
      key: -> { "directory-revoke:#{Directory::AppRevoker.find_by(app_id: arguments.first[:app_id])&.session_scope_key}" }
    )

    # ~4 hours of backoff, so a burst that trips the provider's own rate limit still lands.
    retry_on RevocationFailed, HTTP::Error, HTTP::TimeoutError, wait: :polynomially_longer, attempts: 10 do |job, error|
      Sentry.capture_exception(error, extra: { app_id: job.arguments.first[:app_id] })
    end

    def perform(app_id:, email:)
      revoker = Directory::AppRevoker.find_by(app_id: app_id, enabled: true)
      return unless revoker

      Directory::Revokers.for(revoker).call(email: email)
      revoker.update(last_called_at: Time.current, last_result: "ok")
    rescue RevocationFailed, HTTP::Error, HTTP::TimeoutError => e
      revoker&.update(last_called_at: Time.current, last_result: "failed: #{e.message}")
      raise
    rescue => e
      revoker&.update(last_called_at: Time.current, last_result: "config_error: #{e.message}")
      raise
    end
  end
end
