class RestrictRequirementEntitlementFk < ActiveRecord::Migration[8.0]
  def up
    remove_foreign_key :directory_app_requirements, column: :entitlement_id
    add_foreign_key :directory_app_requirements, :directory_collections, column: :entitlement_id, on_delete: :restrict
  end

  def down
    remove_foreign_key :directory_app_requirements, column: :entitlement_id
    add_foreign_key :directory_app_requirements, :directory_collections, column: :entitlement_id, on_delete: :cascade
  end
end
