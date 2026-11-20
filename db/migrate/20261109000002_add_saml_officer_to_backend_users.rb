# frozen_string_literal: true

class AddSAMLOfficerToBackendUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :backend_users, :is_saml_officer, :boolean, default: false, null: false

    reversible do |dir|
      dir.up do
        execute "UPDATE backend_users SET is_saml_officer = TRUE WHERE id = 1"
      end
    end
  end
end
