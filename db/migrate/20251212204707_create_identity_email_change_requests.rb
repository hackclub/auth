class CreateIdentityEmailChangeRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :identity_email_change_requests do |t|
      t.references :identity, null: false, foreign_key: true
      t.string :new_email, null: false
      t.string :old_email, null: false
      t.datetime :old_email_verified_at
      t.datetime :new_email_verified_at
      t.text :old_email_token_ciphertext
      t.string :old_email_token_bidx
      t.text :new_email_token_ciphertext
      t.string :new_email_token_bidx
      t.datetime :completed_at
      t.datetime :expires_at, null: false
      t.datetime :cancelled_at
      t.string :requested_from_ip

      t.timestamps
    end

    add_index :identity_email_change_requests, :old_email_token_bidx
    add_index :identity_email_change_requests, :new_email_token_bidx
    add_index :identity_email_change_requests, [:identity_id, :completed_at], name: "idx_email_change_requests_identity_completed"
  end
end
