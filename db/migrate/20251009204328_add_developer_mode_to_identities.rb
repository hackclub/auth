class AddDeveloperModeToIdentities < ActiveRecord::Migration[8.0]
  def change
    add_column :identities, :developer_mode, :boolean, default: false, null: false
  end
end
