class AddSeenHintsToBackendUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :backend_users, :seen_hints, :string, array: true, default: []
  end
end
