# frozen_string_literal: true

module Directory
  class AfterChangeJob < ApplicationJob
    queue_as :default

    def perform(change_ids:)
      Rails.logger.info("[Directory] AfterChangeJob processing #{change_ids.size} changes")
      # Phase 2: token revocation and revokers
    end
  end
end
