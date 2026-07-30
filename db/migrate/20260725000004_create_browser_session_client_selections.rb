class CreateBrowserSessionClientSelections < ActiveRecord::Migration[8.0]
  def change
    create_table :browser_session_client_selections do |t|
      t.bigint :browser_session_id, null: false
      t.string :client_kind, null: false
      t.string :client_ref, null: false
      # Points at the identity rather than the session so stickiness survives
      # that account's session expiring.
      t.bigint :identity_id, null: false
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :browser_session_client_selections,
      [ :browser_session_id, :client_kind, :client_ref ],
      unique: true,
      name: "index_client_selections_on_browser_session_and_client"
    add_index :browser_session_client_selections, :identity_id

    add_foreign_key :browser_session_client_selections, :browser_sessions, on_delete: :cascade
    add_foreign_key :browser_session_client_selections, :identities, on_delete: :cascade
  end
end
