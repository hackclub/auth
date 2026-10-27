# frozen_string_literal: true

module Directory
  class MembershipExpirySweepJob < ApplicationJob
    queue_as :default

    def perform
      expired_ids = Directory::Membership.where("expires_at <= ?", Time.current).pluck(:id)
      return if expired_ids.empty?

      expired_ids.each_slice(100) do |batch_ids|
        Directory.mutate!(cause: "sweeper") do
          Directory::Membership.where(id: batch_ids).destroy_all
        end
      end
    end
  end
end
