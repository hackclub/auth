# frozen_string_literal: true

module Stubs
  class Decisioning
    Result = Data.define(:verdict, :signals)

    def self.run(verification)
      verdict = if Flipper.enabled?(:dev_force_manual_review_2026_05_27, verification.identity)
        :manual_review
      elsif Flipper.enabled?(:dev_force_deny_verification_2026_05_27, verification.identity)
        :denied
      else
        :approved
      end

      Result.new(verdict:, signals: [])
    end
  end
end
