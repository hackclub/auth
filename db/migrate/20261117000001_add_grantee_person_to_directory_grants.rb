# frozen_string_literal: true

class AddGranteePersonToDirectoryGrants < ActiveRecord::Migration[8.1]
  def change
    add_reference :directory_grants, :grantee_person, foreign_key: { to_table: :directory_people }, null: true

    # The old composite unique index required grantee_group_id. Replace it with two partial
    # indexes: one for group grants, one for person grants. Each enforces uniqueness within
    # its lane; the XOR validation on the model ensures a grant is in exactly one lane.
    remove_index :directory_grants, name: "idx_grants_unique"

    add_index :directory_grants, [ :grantee_group_id, :target_collection_id, :permission ],
      name: "idx_grants_unique_group", unique: true,
      where: "grantee_group_id IS NOT NULL"

    add_index :directory_grants, [ :grantee_person_id, :target_collection_id, :permission ],
      name: "idx_grants_unique_person", unique: true,
      where: "grantee_person_id IS NOT NULL"

    # Existing rows all have grantee_group_id set; grantee_person_id defaults to NULL.
    # No data migration needed.
  end
end
