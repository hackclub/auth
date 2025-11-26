class CreateIdentityWebauthnCredentials < ActiveRecord::Migration[8.0]
  def change
    create_table :identity_webauthn_credentials do |t|
      t.references :identity, null: false, foreign_key: true
      t.string :external_id
      t.string :public_key
      t.string :nickname
      t.integer :sign_count

      t.timestamps
    end
  end
end
