# frozen_string_literal: true

class AddCanProcessDeletionsToBackendUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :backend_users, :can_process_deletions, :boolean, default: false, null: false
  end
end
