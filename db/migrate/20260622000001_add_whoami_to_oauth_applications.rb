class AddWhoamiToOAuthApplications < ActiveRecord::Migration[8.0]
  def change
    add_column :oauth_applications, :whoami_enabled, :boolean, default: false, null: false
    add_column :oauth_applications, :whoami_allowed_origin, :string
  end
end
