# frozen_string_literal: true

class AllowNullGranteeGroupOnGrants < ActiveRecord::Migration[8.1]
  def change
    change_column_null :directory_grants, :grantee_group_id, true
    add_check_constraint :directory_grants,
      "(grantee_group_id IS NOT NULL) != (grantee_person_id IS NOT NULL)",
      name: "chk_grant_exactly_one_grantee"
  end
end
