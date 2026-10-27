class AddMissingDirectoryFkIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :directory_memberships, :member_person_id,
      where: "member_person_id IS NOT NULL",
      algorithm: :concurrently
    add_index :directory_memberships, :member_group_id,
      where: "member_group_id IS NOT NULL",
      algorithm: :concurrently
    add_index :directory_grants, :target_collection_id,
      algorithm: :concurrently
  end
end
