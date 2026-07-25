class CreatePendingAuthorizations < ActiveRecord::Migration[8.0]
  def change
    create_table :pending_authorizations do |t|
      # The anti-swap binding: a handle may only be resumed by the browser
      # session that created it.
      t.bigint :browser_session_id, null: false
      t.string :token_bidx
      t.text :token_ciphertext
      t.string :kind, null: false
      t.text :payload_ciphertext
      t.datetime :expires_at, null: false
      t.datetime :consumed_at

      t.timestamps
    end

    add_index :pending_authorizations, :token_bidx, unique: true
    add_index :pending_authorizations, :browser_session_id
    add_index :pending_authorizations, :expires_at

    add_foreign_key :pending_authorizations, :browser_sessions, on_delete: :cascade
  end
end
