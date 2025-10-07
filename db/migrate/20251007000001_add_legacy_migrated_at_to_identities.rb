class AddLegacyMigratedAtToIdentities < ActiveRecord::Migration[8.0]
  def change
    add_column :identities, :legacy_migrated_at, :datetime
    add_index :identities, :legacy_migrated_at
  end
end




