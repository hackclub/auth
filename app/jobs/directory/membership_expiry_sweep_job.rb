# frozen_string_literal: true

module Directory
  # Expired memberships are excluded at query time (GraphQueries filters on expires_at),
  # but the derived tables (closure, effective_memberships, effective_grants) only drop
  # them on the next rebuild — and Context#can? reads effective_grants. So every lapsed
  # membership edge, person or nested group, needs a rebuild whether or not anyone was
  # holding an effective membership through it. This job records each newly-lapsed row
  # (activity + paper_trail, see Membership.record_expiries!) and rebuilds in the same
  # transaction, so AfterChangeJob fires any revocations.
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
