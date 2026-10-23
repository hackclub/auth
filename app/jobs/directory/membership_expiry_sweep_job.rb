# frozen_string_literal: true

module Directory
  class MembershipExpirySweepJob < ApplicationJob
    queue_as :default

    def perform
      expired = Directory::Membership.where("expires_at <= ?", Time.current)
      return if expired.none?

      ActiveRecord::Base.transaction do
        expired.destroy_all
        Directory::Rebuild.call(cause: "sweeper")
      end
    end
  end
end
