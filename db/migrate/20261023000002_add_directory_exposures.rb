class AddDirectoryExposures < ActiveRecord::Migration[8.0]
  def change
    create_table :directory_exposures do |t|
      t.references :app, null: false, foreign_key: { to_table: :oauth_applications, on_delete: :cascade }
      t.references :entitlement, null: false, foreign_key: { to_table: :directory_collections, on_delete: :cascade }
      t.text :claim_name, null: false
      t.references :created_by_identity, foreign_key: { to_table: :identities, on_delete: :nullify }
      t.timestamptz :created_at, null: false, default: -> { "now()" }

      t.index %i[app_id entitlement_id], unique: true
      t.index %i[app_id claim_name], unique: true
    end

    create_table :directory_app_requirements, id: false do |t|
      t.references :app, null: false, foreign_key: { to_table: :oauth_applications, on_delete: :cascade }
      t.references :entitlement, null: false, foreign_key: { to_table: :directory_collections, on_delete: :cascade }

      t.index %i[app_id entitlement_id], unique: true
    end

    create_table :directory_app_revokers, id: false do |t|
      t.references :app, null: false, primary_key: true, foreign_key: { to_table: :oauth_applications, on_delete: :cascade }
      t.text :adapter, null: false
      t.text :config_ciphertext, null: false
      t.boolean :enabled, null: false, default: true
      t.timestamptz :last_called_at
      t.text :last_result
    end
  end
end
