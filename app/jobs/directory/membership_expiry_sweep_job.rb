# frozen_string_literal: true

module Directory
  class MembershipExpirySweepJob < ApplicationJob
    queue_as :default

    def perform
      expired = Directory::Membership
        .where("expires_at <= ?", Time.current)
        .includes(:collection, :member_person)

      expired_records = expired.to_a
      return if expired_records.empty?

      expired_ids = expired_records.map(&:id)
      summary = expired_records.map { |m|
        { id: m.id, collection: m.collection&.name, member: m.member_person&.full_name }
      }

      Directory.mutate!(cause: "sweeper") do
        Directory::Membership.where(id: expired_ids).delete_all
      end

      PublicActivity::Activity.create!(
        trackable_type: "Directory::Membership",
        key: "membership.batch_expired",
        parameters: { count: summary.size, details: summary.first(50) }
      )
    end
  end
end
