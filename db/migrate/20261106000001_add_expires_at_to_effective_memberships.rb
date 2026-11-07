# frozen_string_literal: true

class AddExpiresAtToEffectiveMemberships < ActiveRecord::Migration[8.0]
  def change
    add_column :directory_effective_memberships, :expires_at, :datetime
    add_index :directory_effective_memberships, :expires_at,
      where: "expires_at IS NOT NULL",
      name: "idx_effective_memberships_expires_at"
  end
end
