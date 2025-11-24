class AddTrustLevelToPrograms < ActiveRecord::Migration[8.0]
  def change
    add_column :oauth_applications, :trust_level, :integer, default: 0, null: false
  end
end
