class RemoveSlackIdFromBackendUsers < ActiveRecord::Migration[8.0]
  def change
    remove_column :backend_users, :slack_id, :string
  end
end
