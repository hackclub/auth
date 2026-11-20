# frozen_string_literal: true

class AddCanBanToBackendUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :backend_users, :can_ban, :boolean, default: false, null: false
  end
end
