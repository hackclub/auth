class AddExtendedFieldsToPersonaRecords < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_persona_records, :name_middle, :string
    add_column :identity_persona_records, :sex, :string
    add_column :identity_persona_records, :document_number, :text
    add_column :identity_persona_records, :issue_date, :date
    add_column :identity_persona_records, :issuing_authority, :string
    add_column :identity_persona_records, :address_street_1, :string
    add_column :identity_persona_records, :address_street_2, :string
    add_column :identity_persona_records, :address_city, :string
    add_column :identity_persona_records, :address_subdivision, :string
    add_column :identity_persona_records, :address_postal_code, :string
    add_column :identity_persona_records, :behaviors, :jsonb, default: {}
  end
end
