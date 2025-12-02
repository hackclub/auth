class AddPhoneNumberToAddresses < ActiveRecord::Migration[8.0]
  def change
    add_column :addresses, :phone_number, :string
  end
end
