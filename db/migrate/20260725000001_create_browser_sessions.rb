class CreateBrowserSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :browser_sessions do |t|
      t.string :token_bidx
      t.text :token_ciphertext
      t.bigint :active_identity_session_id
      t.datetime :expires_at, null: false
      t.datetime :last_seen

      t.timestamps
    end

    add_index :browser_sessions, :token_bidx, unique: true
    add_index :browser_sessions, :expires_at
    add_index :browser_sessions, :active_identity_session_id

    add_foreign_key :browser_sessions, :identity_sessions,
      column: :active_identity_session_id, on_delete: :nullify
  end
end
