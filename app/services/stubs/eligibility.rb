# frozen_string_literal: true

module Stubs
  class Eligibility
    def self.manual_flow?(user) = Flipper.enabled?(:dev_allow_manual_flow_2026_05_27, user)
  end
end
