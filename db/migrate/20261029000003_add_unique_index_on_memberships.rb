class AddUniqueIndexOnMemberships < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :directory_memberships, [:collection_id, :member_person_id],
      unique: true,
      where: "member_person_id IS NOT NULL",
      name: "idx_uniq_membership_person",
      algorithm: :concurrently
    add_index :directory_memberships, [:collection_id, :member_group_id],
      unique: true,
      where: "member_group_id IS NOT NULL",
      name: "idx_uniq_membership_group",
      algorithm: :concurrently
  end
end
