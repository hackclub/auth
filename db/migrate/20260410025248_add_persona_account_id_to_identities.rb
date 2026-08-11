class AddPersonaAccountIdToIdentities < ActiveRecord::Migration[8.0]
  def change
    add_column :identities, :persona_account_id, :string
    add_index :identities, :persona_account_id, unique: true
  end
end
