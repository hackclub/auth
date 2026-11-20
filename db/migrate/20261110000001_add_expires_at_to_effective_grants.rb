class AddExpiresAtToEffectiveGrants < ActiveRecord::Migration[8.0]
  def change
    add_column :directory_effective_grants, :expires_at, :datetime
  end
end
