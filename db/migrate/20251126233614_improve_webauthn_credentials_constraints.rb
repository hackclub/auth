class ImproveWebauthnCredentialsConstraints < ActiveRecord::Migration[8.0]
  def change
    change_column_null :identity_webauthn_credentials, :external_id, false
    change_column_null :identity_webauthn_credentials, :public_key, false
    add_index :identity_webauthn_credentials, :external_id, unique: true, if_not_exists: true
    add_index :identity_webauthn_credentials, :identity_id, if_not_exists: true
  end
end
