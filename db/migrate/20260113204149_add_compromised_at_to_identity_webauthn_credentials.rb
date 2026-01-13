class AddCompromisedAtToIdentityWebauthnCredentials < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_webauthn_credentials, :compromised_at, :datetime
  end
end
