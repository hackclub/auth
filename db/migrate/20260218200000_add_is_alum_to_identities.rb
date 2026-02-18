class AddIsAlumToIdentities < ActiveRecord::Migration[8.0]
  def change
    add_column :identities, :is_alum, :boolean, default: false
  end
end
