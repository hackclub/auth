class AddConfirmDestroyToCollections < ActiveRecord::Migration[8.0]
  def change
    add_column :directory_collections, :confirm_destroy, :boolean, default: false, null: false
    reversible do |dir|
      dir.up do
        execute "UPDATE directory_collections SET confirm_destroy = protected"
      end
    end
  end
end
