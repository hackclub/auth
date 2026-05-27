# frozen_string_literal: true

module Stubs
  class Decisioning
    def self.run(verification)
      if Flipper.enabled?(:force_manual_review, verification.identity)
        :manual_review
      elsif Flipper.enabled?(:force_deny_verification, verification.identity)
        :denied
      else
        :approved
      end
    end
  end
end
