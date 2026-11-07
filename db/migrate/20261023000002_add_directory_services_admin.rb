# frozen_string_literal: true

class AddDirectoryServicesAdmin < ActiveRecord::Migration[8.0]
  def change
    add_column :backend_users, :directory_services_admin, :boolean, default: false, null: false
  end
end
