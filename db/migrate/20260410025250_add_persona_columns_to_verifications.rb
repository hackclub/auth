class AddPersonaColumnsToVerifications < ActiveRecord::Migration[8.0]
  def change
    add_column :verifications, :persona_inquiry_id, :string
    add_column :verifications, :persona_session_token, :text
    add_reference :verifications, :persona_record, foreign_key: { to_table: :identity_persona_records }

    add_index :verifications, :persona_inquiry_id
  end
end
