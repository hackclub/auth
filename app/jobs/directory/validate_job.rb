# frozen_string_literal: true

module Directory
  class ValidateJob < ApplicationJob
    queue_as :default

    def perform
      result = Directory::Validate.call

      if result.valid?
        Rails.logger.info("[Directory] Validate: OK")
      else
        Rails.logger.error("[Directory] Validate: DRIFT DETECTED — #{result.mismatches}")
        Sentry.capture_message("Directory drift detected", level: :error, extra: { mismatches: result.mismatches }) if defined?(Sentry)
      end
    end
  end
end
