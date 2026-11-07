class AddIndexOnDirectoryClosureDescendantId < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :directory_closure, :descendant_id, algorithm: :concurrently
  end
end
