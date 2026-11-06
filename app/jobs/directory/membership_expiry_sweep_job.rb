# frozen_string_literal: true

module Directory
  class MembershipExpirySweepJob < ApplicationJob
    queue_as :default

    def perform
      return unless Directory::Membership.where("expires_at <= ?", Time.current).exists?

      summary = []

      Directory.mutate!(cause: Directory.cause("sweeper")) do
        expired = Directory::Membership
          .where("expires_at <= ?", Time.current)
          .includes(:collection, :member_person)
          .to_a

        if expired.any?
          summary = expired.map { |m|
            { id: m.id, collection: m.collection&.name, member: m.member_person&.full_name }
          }

          expired.each(&:destroy!)
        end
      end

      return if summary.empty?

      PublicActivity::Activity.create!(
        trackable_type: "Directory::Membership",
        key: "membership.batch_expired",
        parameters: { count: summary.size, details: summary.first(50) }
      )
    end
  end
end
