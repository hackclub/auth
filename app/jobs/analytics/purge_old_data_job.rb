# frozen_string_literal: true

module Analytics
  class PurgeOldDataJob < ApplicationJob
    queue_as :default

    RETENTION_DAYS = 90

    def perform
      cutoff = RETENTION_DAYS.days.ago

      events_deleted = Ahoy::Event.where("time < ?", cutoff).delete_all
      Rails.logger.info "Analytics purge: deleted #{events_deleted} events"

      visits_deleted = Ahoy::Visit
        .where("started_at < ?", cutoff)
        .where.not(id: Ahoy::Event.select(:visit_id).where.not(visit_id: nil))
        .delete_all
      Rails.logger.info "Analytics purge: deleted #{visits_deleted} orphaned visits"
    end
  end
end
