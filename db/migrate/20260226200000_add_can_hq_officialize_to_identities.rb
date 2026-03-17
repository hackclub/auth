class AddCanHqOfficializeToIdentities < ActiveRecord::Migration[8.0]
  def change
    add_column :identities, :can_hq_officialize, :boolean, default: false, null: false
  end
end
