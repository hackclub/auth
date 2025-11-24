class AddPromoteClickCountToIdentities < ActiveRecord::Migration[8.0]
  def change
    add_column :identities, :promote_click_count, :integer, default: 0
  end
end
