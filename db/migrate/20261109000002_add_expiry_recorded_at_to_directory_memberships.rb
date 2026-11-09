class AddExpiryRecordedAtToDirectoryMemberships < ActiveRecord::Migration[8.0]
  # set by MembershipExpirySweepJob once a lapsed membership has been audited and the
  # derived tables rebuilt without it; NULL + expires_at in the past = still to sweep
  def change
    add_column :directory_memberships, :expiry_recorded_at, :datetime
  end
end
