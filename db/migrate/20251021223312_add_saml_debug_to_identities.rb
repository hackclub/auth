class AddSAMLDebugToIdentities < ActiveRecord::Migration[8.0]
  def change
    add_column :identities, :saml_debug, :boolean
  end
end
