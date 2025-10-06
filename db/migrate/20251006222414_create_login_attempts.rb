class CreateLoginAttempts < ActiveRecord::Migration[8.0]
  def change
    create_table :login_attempts do |t|
      t.references :identity, null: false, foreign_key: true
      t.references :session, null: true, foreign_key: {to_table: :identity_sessions}
      t.string :aasm_state
      t.jsonb :authentication_factors
      t.text :browser_token_ciphertext

      t.timestamps
    end
  end
end
