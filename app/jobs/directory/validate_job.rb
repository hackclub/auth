# frozen_string_literal: true

module Directory
  class ValidateJob < ApplicationJob
    queue_as :default

    # change rows only matter to the AfterChangeJob enqueued alongside them
    CHANGE_RETENTION = 30.days

    def perform
      Directory::MembershipChange.where(created_at: ...CHANGE_RETENTION.ago).in_batches(of: 10_000).delete_all

      result = Directory::Validate.call
      Rails.cache.write("directory:validate_result", { result: result, at: Time.current })

      if result.valid?
        Rails.logger.info("[Directory] Validate: OK")
      else
        Rails.logger.error("[Directory] Validate: DRIFT DETECTED — #{result.mismatches}")
        Sentry.capture_message("Directory drift detected", level: :error, extra: { mismatches: result.mismatches }) if defined?(Sentry)
      end
    end
  end
end
