# frozen_string_literal: true

module Directory
  # Expired memberships are excluded at query time (GraphQueries filters on
  # expires_at), so they stop being "effective" the moment they expire — no
  # sweep needed for correctness. This job just triggers a rebuild so the
  # derived tables catch up and AfterChangeJob fires any revocations.
  class MembershipExpirySweepJob < ApplicationJob
    queue_as :default

    def perform
      return unless Directory::EffectiveMembership.unscoped.where("expires_at <= NOW()").exists?

      Directory.mutate!(cause: Directory.cause("expiry_rebuild")) {}
    end
  end
end
