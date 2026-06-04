class RemovePiiColumnsFromPersonaRecords < ActiveRecord::Migration[8.0]
  def change
    remove_column :identity_persona_records, :name_middle, :string
    remove_column :identity_persona_records, :sex, :string
    remove_column :identity_persona_records, :document_number, :text
    remove_column :identity_persona_records, :issue_date, :date
    remove_column :identity_persona_records, :issuing_authority, :string
    remove_column :identity_persona_records, :address_street_1, :string
    remove_column :identity_persona_records, :address_street_2, :string
    remove_column :identity_persona_records, :address_city, :string
    remove_column :identity_persona_records, :address_subdivision, :string
    remove_column :identity_persona_records, :address_postal_code, :string
  end
end
