class AddDisallowSlackToIdentities < ActiveRecord::Migration[8.0]
  def change
    add_column :identities, :disallow_slack, :boolean, default: false, null: false
  end
end
