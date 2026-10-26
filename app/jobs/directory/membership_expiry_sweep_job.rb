# frozen_string_literal: true

module Directory
  class MembershipExpirySweepJob < ApplicationJob
    queue_as :default

    def perform
      expired = Directory::Membership.where("expires_at <= ?", Time.current)
      return if expired.none?

      Directory.mutate!(cause: "sweeper") { expired.destroy_all }
    end
  end
end
