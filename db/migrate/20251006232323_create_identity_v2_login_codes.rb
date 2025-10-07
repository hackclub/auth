class CreateIdentityV2LoginCodes < ActiveRecord::Migration[8.0]
  def change
    create_table :identity_v2_login_codes do |t|
      t.text :code
      t.inet :ip_address
      t.datetime :used_at
      t.text :user_agent
      t.references :identity, null: false, foreign_key: true

      t.timestamps
    end
  end
end
