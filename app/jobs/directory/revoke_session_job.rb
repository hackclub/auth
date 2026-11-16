# frozen_string_literal: true

module Directory
  class RevokeSessionJob < ApplicationJob
    include GoodJob::ActiveJobExtensions::Concurrency

    queue_as :default

    class RevocationFailed < StandardError; end

    # Revokers::Outbound turns every network failure into RevocationFailed; the rest are
    # belt and braces for anything raised before it gets the chance
    TRANSIENT = [ RevocationFailed, SystemCallError, IOError, OpenSSL::SSL::SSLError, Timeout::Error ].freeze

    # Cloudflare's API allows ~1200 requests per 5 minutes per token; stay under it per
    # account. Throttled jobs are rescheduled by GoodJob, not counted as failures.
    good_job_control_concurrency_with(
      perform_throttle: [ 1000, 5.minutes ],
      key: -> { "directory-revoke:#{Directory::RevokeSessionJob.throttle_scope(arguments.first[:app_id])}" }
    )

    # ~4 hours of backoff, so a burst that trips the provider's own rate limit still lands.
    retry_on(*TRANSIENT, wait: :polynomially_longer, attempts: 10) do |job, error|
      Sentry.capture_exception(error, extra: { app_id: job.arguments.first[:app_id] })
    end

    def self.throttle_scope(app_id)
      Directory::AppRevoker.find_by(app_id: app_id)&.session_scope_key
    rescue *Directory::AppRevoker::UNREADABLE
      "app:#{app_id}"
    end

    # fallback_app_ids: other apps sharing this revoker scope; tried in order if this app's
    # revoker is gone, disabled or failing. one success is enough.
    def perform(app_id:, email:, fallback_app_ids: [])
      revokers = Directory::AppRevoker.where(app_id: [ app_id, *fallback_app_ids ], enabled: true).index_by(&:app_id)
      candidates = [ app_id, *fallback_app_ids ].filter_map { |id| revokers[id] }
      return if candidates.empty?

      errors = []
      newly_broken = []
      candidates.each do |revoker|
        before = revoker.last_result
        return if attempt(revoker, email)
      rescue => e
        errors << e
        newly_broken << e if !transient?(e) && revoker.last_result != before
      end

      # a transient failure anywhere means a retry can still land, whatever failed last.
      # a broken revoker is reported when it breaks (or breaks differently), not on every
      # retry, every job, or a dashboard retry of the same breakage: the revoker row
      # remembers what it last said. whatever's raised is reported as the job's own error.
      raised = errors.find { |e| transient?(e) } || errors.last
      (newly_broken - [ raised ]).each { |e| Sentry.capture_exception(e, extra: { app_id: app_id }) }
      raise raised
    end

    private

    def transient?(error) = TRANSIENT.any? { |klass| error.is_a?(klass) }

    def attempt(revoker, email)
      Directory::Revokers.for(revoker).call(email: email)
      revoker.update_columns(last_called_at: Time.current, last_result: "ok")
      true
    rescue *TRANSIENT => e
      revoker.update_columns(last_called_at: Time.current, last_result: "failed: #{e.message}".truncate(500))
      raise
    rescue => e
      revoker.update_columns(last_called_at: Time.current, last_result: "config_error: #{e.message}".truncate(500))
      raise
    end
  end
end
