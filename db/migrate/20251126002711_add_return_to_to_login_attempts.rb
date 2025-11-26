class AddReturnToToLoginAttempts < ActiveRecord::Migration[8.0]
  def change
    add_column :login_attempts, :return_to, :string, if_not_exists: true
  end
end
