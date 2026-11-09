# frozen_string_literal: true

module Directory
  # the derived tables only drop a lapsed membership on the next rebuild, and Context#can?
  # reads effective_grants, so every lapsed edge (person or nested group) needs one, even
  # when nobody held an effective membership through it.
  class MembershipExpirySweepJob < ApplicationJob
    queue_as :default

    def perform
      return unless Directory::Membership.expiry_unrecorded.exists?

      Directory.mutate!(cause: Directory.cause("expiry_rebuild")) do
        Directory::Membership.record_expiries!
      end
    end
  end
end
