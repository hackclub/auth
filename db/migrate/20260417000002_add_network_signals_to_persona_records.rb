class AddNetworkSignalsToPersonaRecords < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_persona_records, :network_signals, :jsonb, default: {}
  end
end
