class AddInvalidatedAtToV2LoginCodes < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_v2_login_codes, :invalidated_at, :datetime
  end
end
