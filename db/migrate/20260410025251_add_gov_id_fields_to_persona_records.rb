class AddGovIdFieldsToPersonaRecords < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_persona_records, :id_class, :string
    add_column :identity_persona_records, :expiration_date, :date
    add_column :identity_persona_records, :entity_confidence_score, :float
    add_column :identity_persona_records, :checks, :jsonb, default: []
  end
end
