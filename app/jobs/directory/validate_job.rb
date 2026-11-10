# frozen_string_literal: true

module Directory
  class ValidateJob < ApplicationJob
    queue_as :default

    # raised so the run is recorded as failed in good_jobs, which /directory/health reads
    class DriftDetected < StandardError; end

    # change rows only matter to the AfterChangeJob enqueued alongside them
    CHANGE_RETENTION = 30.days

    def self.summary(result)
      result.mismatches.filter_map do |table, diff|
        next if diff.values.all?(&:empty?)
        "#{table}: #{diff.fetch(:missing, []).size} missing, #{diff.fetch(:extra, []).size} extra, #{diff.fetch(:stale, []).size} stale expiry"
      end.join("; ")
    end

    def self.last_run
      GoodJob::Job.where(job_class: name).where.not(finished_at: nil).order(finished_at: :desc).first
    end

    def perform
      Directory::MembershipChange.where(created_at: ...CHANGE_RETENTION.ago).in_batches(of: 10_000).delete_all

      result = Directory::Validate.call
      if result.valid?
        Rails.logger.info("[Directory] Validate: OK")
      else
        Rails.logger.error("[Directory] Validate: DRIFT DETECTED — #{result.mismatches}")
        raise DriftDetected, "directory drift detected — #{self.class.summary(result)}"
      end
    end
  end
end
