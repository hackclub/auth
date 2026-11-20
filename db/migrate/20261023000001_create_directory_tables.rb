class CreateDirectoryTables < ActiveRecord::Migration[8.0]
  def change
    add_column :backend_users, :directory_services_admin, :boolean, default: false, null: false

    create_table "directory_app_requirements", id: false do |t|
      t.bigint "app_id", null: false
      t.bigint "entitlement_id", null: false
      t.index [ "app_id", "entitlement_id" ], name: "index_directory_app_requirements_on_app_id_and_entitlement_id", unique: true
      t.index [ "app_id" ], name: "index_directory_app_requirements_on_app_id"
      t.index [ "entitlement_id" ], name: "index_directory_app_requirements_on_entitlement_id"
    end

    create_table "directory_app_revokers", primary_key: "app_id" do |t|
      t.text "adapter", null: false
      t.text "config_ciphertext", null: false
      t.boolean "enabled", default: true, null: false
      t.timestamptz "last_called_at"
      t.text "last_result"
      t.index [ "app_id" ], name: "index_directory_app_revokers_on_app_id"
    end

    create_table "directory_closure", primary_key: [ "ancestor_id", "descendant_id" ] do |t|
      t.bigint "ancestor_id", null: false
      t.bigint "descendant_id", null: false
      t.integer "depth", null: false
      t.index [ "descendant_id" ], name: "index_directory_closure_on_descendant_id"
    end

    create_table "directory_collections" do |t|
      t.string "slug", null: false
      t.string "name", null: false
      t.string "kind", null: false
      t.boolean "protected", default: false, null: false
      t.text "description"
      t.bigint "created_by_identity_id"
      t.datetime "created_at", null: false
      t.boolean "confirm_destroy", default: false, null: false
      t.index [ "slug" ], name: "index_directory_collections_on_slug", unique: true
      t.check_constraint "kind IN ('group', 'entitlement')", name: "chk_collection_kind"
    end

    create_table "directory_effective_grants", primary_key: [ "person_id", "target_collection_id", "permission" ] do |t|
      t.bigint "person_id", null: false
      t.bigint "target_collection_id", null: false
      t.string "permission", null: false
      t.index [ "target_collection_id" ], name: "index_directory_effective_grants_on_target_collection_id"
    end

    create_table "directory_effective_memberships", primary_key: [ "collection_id", "person_id" ] do |t|
      t.bigint "collection_id", null: false
      t.bigint "person_id", null: false
      t.datetime "expires_at"
      t.index [ "expires_at" ], name: "idx_effective_memberships_expires_at", where: "(expires_at IS NOT NULL)"
      t.index [ "person_id" ], name: "index_directory_effective_memberships_on_person_id"
    end

    create_table "directory_exposures" do |t|
      t.bigint "app_id", null: false
      t.bigint "entitlement_id", null: false
      t.text "claim_name", null: false
      t.bigint "created_by_identity_id"
      t.timestamptz "created_at", default: -> { "now()" }, null: false
      t.index [ "app_id", "claim_name" ], name: "index_directory_exposures_on_app_id_and_claim_name", unique: true
      t.index [ "app_id", "entitlement_id" ], name: "index_directory_exposures_on_app_id_and_entitlement_id", unique: true
      t.index [ "app_id" ], name: "index_directory_exposures_on_app_id"
      t.index [ "created_by_identity_id" ], name: "index_directory_exposures_on_created_by_identity_id"
      t.index [ "entitlement_id" ], name: "index_directory_exposures_on_entitlement_id"
    end

    create_table "directory_grants" do |t|
      t.bigint "grantee_group_id", null: false
      t.bigint "target_collection_id", null: false
      t.string "permission", null: false
      t.boolean "recursive", default: false, null: false
      t.bigint "created_by_identity_id"
      t.datetime "created_at", null: false
      t.index [ "grantee_group_id", "target_collection_id", "permission" ], name: "idx_grants_unique", unique: true
      t.index [ "target_collection_id" ], name: "index_directory_grants_on_target_collection_id"
      t.check_constraint "permission IN ('view', 'manage_members', 'expose')", name: "chk_grant_permission"
    end

    create_table "directory_membership_changes" do |t|
      t.bigint "collection_id", null: false
      t.bigint "person_id", null: false
      t.string "op", null: false
      t.text "cause"
      t.datetime "created_at", null: false
      t.index [ "created_at" ], name: "index_directory_membership_changes_on_created_at"
      t.check_constraint "op IN ('added', 'removed')", name: "chk_membership_change_op"
    end

    create_table "directory_memberships" do |t|
      t.bigint "collection_id", null: false
      t.bigint "member_person_id"
      t.bigint "member_group_id"
      t.bigint "created_by_identity_id"
      t.datetime "expires_at"
      t.datetime "created_at", null: false
      t.datetime "expiry_recorded_at"
      t.index [ "collection_id", "member_group_id" ], name: "idx_membership_group_unique", unique: true, where: "(member_group_id IS NOT NULL)"
      t.index [ "collection_id", "member_person_id" ], name: "idx_membership_person_unique", unique: true, where: "(member_person_id IS NOT NULL)"
      t.index [ "collection_id" ], name: "index_directory_memberships_on_collection_id"
      t.index [ "member_group_id" ], name: "index_directory_memberships_on_member_group_id", where: "(member_group_id IS NOT NULL)"
      t.index [ "member_person_id" ], name: "index_directory_memberships_on_member_person_id", where: "(member_person_id IS NOT NULL)"
      t.check_constraint "member_group_id != collection_id", name: "chk_membership_no_self_reference"
      t.check_constraint "(member_person_id IS NOT NULL AND member_group_id IS NULL) OR (member_person_id IS NULL AND member_group_id IS NOT NULL)", name: "chk_membership_exactly_one_member"
    end

    create_table "directory_people" do |t|
      t.bigint "identity_id", null: false
      t.bigint "created_by_identity_id"
      t.datetime "created_at", null: false
      t.index [ "identity_id" ], name: "index_directory_people_on_identity_id", unique: true
    end

    add_foreign_key "directory_app_requirements", "directory_collections", column: "entitlement_id", on_delete: :restrict
    add_foreign_key "directory_app_requirements", "oauth_applications", column: "app_id", on_delete: :cascade
    add_foreign_key "directory_app_revokers", "oauth_applications", column: "app_id", on_delete: :cascade
    add_foreign_key "directory_closure", "directory_collections", column: "ancestor_id", on_delete: :cascade
    add_foreign_key "directory_closure", "directory_collections", column: "descendant_id", on_delete: :cascade
    add_foreign_key "directory_collections", "identities", column: "created_by_identity_id", on_delete: :nullify
    add_foreign_key "directory_effective_grants", "directory_collections", column: "target_collection_id", on_delete: :cascade
    add_foreign_key "directory_effective_grants", "directory_people", column: "person_id", on_delete: :cascade
    add_foreign_key "directory_effective_memberships", "directory_collections", column: "collection_id", on_delete: :cascade
    add_foreign_key "directory_effective_memberships", "directory_people", column: "person_id", on_delete: :cascade
    add_foreign_key "directory_exposures", "directory_collections", column: "entitlement_id", on_delete: :cascade
    add_foreign_key "directory_exposures", "identities", column: "created_by_identity_id", on_delete: :nullify
    add_foreign_key "directory_exposures", "oauth_applications", column: "app_id", on_delete: :cascade
    add_foreign_key "directory_grants", "directory_collections", column: "grantee_group_id", on_delete: :cascade
    add_foreign_key "directory_grants", "directory_collections", column: "target_collection_id", on_delete: :cascade
    add_foreign_key "directory_grants", "identities", column: "created_by_identity_id", on_delete: :nullify
    add_foreign_key "directory_memberships", "directory_collections", column: "collection_id", on_delete: :cascade
    add_foreign_key "directory_memberships", "directory_collections", column: "member_group_id", on_delete: :cascade
    add_foreign_key "directory_memberships", "directory_people", column: "member_person_id", on_delete: :cascade
    add_foreign_key "directory_memberships", "identities", column: "created_by_identity_id", on_delete: :nullify
    add_foreign_key "directory_people", "identities"
    add_foreign_key "directory_people", "identities", column: "created_by_identity_id", on_delete: :nullify
  end
end
