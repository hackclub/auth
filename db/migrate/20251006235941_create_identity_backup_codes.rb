class CreateIdentityBackupCodes < ActiveRecord::Migration[8.0]
  def change
    create_table :identity_backup_codes do |t|
      t.string :aasm_state, default: 'previewed', null: false
      t.text :code_digest, null: false
      t.references :identity, null: false, foreign_key: true

      t.timestamps
    end
  end
end
