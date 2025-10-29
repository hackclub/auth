class AddIsInWorkspaceToIdentities < ActiveRecord::Migration[8.0]
  def change
    add_column :identities, :is_in_workspace, :boolean, default: false, null: false
  end
end
