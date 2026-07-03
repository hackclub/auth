class AddTwoFactorRequiredToIdentities < ActiveRecord::Migration[8.0]
  def change
    add_column :identities, :two_factor_required, :boolean, default: false, null: false
  end
end
