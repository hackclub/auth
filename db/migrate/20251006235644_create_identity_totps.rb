class CreateIdentityTotps < ActiveRecord::Migration[8.0]
  def change
    create_table :identity_totps do |t|
      t.string :aasm_state
      t.datetime :deleted_at
      t.datetime :last_used_at
      t.text :secret_ciphertext
      t.references :identity, null: false, foreign_key: true

      t.timestamps
    end
  end
end
