# frozen_string_literal: true

module Stubs
  class Eligibility
    def self.manual_flow?(user) = Flipper.enabled?(:allow_manual_flow, user)
  end
end
