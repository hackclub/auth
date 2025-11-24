class AddOwnerIdentityIdToOAuthApplications < ActiveRecord::Migration[8.0]
  def change
    add_column :oauth_applications, :owner_identity_id, :bigint, null: true
    add_index :oauth_applications, :owner_identity_id
  end
end
