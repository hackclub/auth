class AddLockedAtToIdentities < ActiveRecord::Migration[8.0]
  def change
    add_column :identities, :locked_at, :datetime
  end
end
