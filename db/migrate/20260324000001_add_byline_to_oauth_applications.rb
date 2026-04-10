class AddBylineToOAuthApplications < ActiveRecord::Migration[8.0]
  def change
    add_column :oauth_applications, :byline, :string
  end
end
