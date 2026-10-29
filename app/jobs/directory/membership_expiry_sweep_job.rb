# frozen_string_literal: true

module Directory
  class MembershipExpirySweepJob < ApplicationJob
    queue_as :default

    def perform
      summary = []

      Directory.mutate!(cause: "sweeper") do
        expired = Directory::Membership
          .where("expires_at <= ?", Time.current)
          .includes(:collection, :member_person)
          .to_a

        next if expired.empty?

        summary = expired.map { |m|
          { id: m.id, collection: m.collection&.name, member: m.member_person&.full_name }
        }

        Directory::Membership.where(id: expired.map(&:id)).delete_all
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
