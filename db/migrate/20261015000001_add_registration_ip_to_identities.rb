class AddRegistrationIpToIdentities < ActiveRecord::Migration[8.0]
  def change
    add_column :identities, :registration_ip, :string
  end
end
