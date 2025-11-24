class AddUse2faToIdentities < ActiveRecord::Migration[8.0]
  def change
    add_column :identities, :use_two_factor_authentication, :boolean
  end
end
