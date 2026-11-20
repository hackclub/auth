class AddBehaviorsToPersonaRecords < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_persona_records, :behaviors, :jsonb, default: {}
  end
end
