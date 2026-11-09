class AddIndexOnDirectoryMembershipsCollectionId < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  # the unique indexes on (collection_id, member_*) are partial, so a bare
  # collection_id lookup (member counts, collection deletes) can't use them
  def change
    add_index :directory_memberships, :collection_id, algorithm: :concurrently
  end
end
