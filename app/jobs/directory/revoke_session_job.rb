# frozen_string_literal: true

module Directory
  class RevokeSessionJob < ApplicationJob
    include GoodJob::ActiveJobExtensions::Concurrency

    queue_as :default

    class RevocationFailed < StandardError; end

    # http.rb wraps socket errors in HTTP::Error, but not TLS failures or bare timeouts
    TRANSIENT = [ RevocationFailed, HTTP::Error, OpenSSL::SSL::SSLError, Timeout::Error, EOFError ].freeze

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
      candidates.each do |revoker|
        return if attempt(revoker, email)
      rescue => e
        errors << e
      end

      # a transient failure anywhere means a retry can still land, whatever failed last
      transient, broken = errors.partition { |e| TRANSIENT.any? { |klass| e.is_a?(klass) } }
      # a broken revoker stays broken across retries, so say so once, on the first real
      # attempt. when nothing is transient the last one is raised and the job error reports it
      reported = transient.any? ? broken : broken[0...-1]
      reported.each { |e| Sentry.capture_exception(e, extra: { app_id: app_id }) } if first_real_attempt?
      raise transient.first if transient.any?

      raise broken.last
    end

    private

    # executions also counts GoodJob's throttle retries, which never reached perform's work;
    # only retries for our own transient failures mean this already ran (and reported)
    def first_real_attempt?
      (exception_executions || {})[TRANSIENT.to_s].to_i.zero?
    end

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
