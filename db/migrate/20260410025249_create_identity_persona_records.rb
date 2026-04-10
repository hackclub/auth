class CreateIdentityPersonaRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :identity_persona_records do |t|
      t.references :identity, null: false, foreign_key: true
      t.string :inquiry_id, null: false
      t.text :raw_json_response
      t.string :name_first
      t.string :name_last
      t.date :birthdate
      t.string :country_code
      t.string :persona_status
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :identity_persona_records, :inquiry_id, unique: true
    add_index :identity_persona_records, :deleted_at
  end
end
