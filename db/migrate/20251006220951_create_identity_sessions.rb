class CreateIdentitySessions < ActiveRecord::Migration[8.0]
  def change
    create_table :identity_sessions do |t|
      t.string :device_info
      t.datetime :expires_at
      t.string :fingerprint
      t.string :ip
      t.datetime :last_seen
      t.decimal :latitude
      t.decimal :longitude
      t.string :os_info
      t.string :session_token_bidx
      t.text :session_token_ciphertext
      t.datetime :signed_out_at
      t.string :timezone
      t.references :identity, null: false, foreign_key: true

      t.timestamps
    end
  end
end
