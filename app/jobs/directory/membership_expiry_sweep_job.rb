# frozen_string_literal: true

module Directory
  class MembershipExpirySweepJob < ApplicationJob
    queue_as :default

    def perform
      expired_ids = Directory::Membership.where("expires_at <= ?", Time.current).pluck(:id)
      return if expired_ids.empty?

      Directory.mutate!(cause: "sweeper") do
        Directory::Membership.where(id: expired_ids).destroy_all
      end
    end
  end
end
