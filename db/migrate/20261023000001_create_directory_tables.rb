class CreateDirectoryTables < ActiveRecord::Migration[8.0]
  def up
    add_column :backend_users, :directory_services_admin, :boolean, default: false, null: false

    create_table :directory_people, id: :bigint do |t|
      t.bigint :identity_id, null: false
      t.bigint :created_by_identity_id
      t.datetime :created_at, null: false

      t.index :identity_id, unique: true
      t.foreign_key :identities, column: :identity_id
      t.foreign_key :identities, column: :created_by_identity_id, on_delete: :nullify
    end

    create_table :directory_collections, id: :bigint do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.string :kind, null: false
      t.boolean :protected, default: false, null: false
      t.text :description
      t.bigint :created_by_identity_id
      t.datetime :created_at, null: false

      t.index :slug, unique: true
      t.check_constraint "kind IN ('group', 'entitlement')", name: "chk_collection_kind"
      t.foreign_key :identities, column: :created_by_identity_id, on_delete: :nullify
    end

    create_table :directory_memberships, id: :bigint do |t|
      t.bigint :collection_id, null: false
      t.bigint :member_person_id
      t.bigint :member_group_id
      t.bigint :created_by_identity_id
      t.datetime :expires_at
      t.datetime :created_at, null: false

      t.check_constraint "(member_person_id IS NOT NULL AND member_group_id IS NULL) OR (member_person_id IS NULL AND member_group_id IS NOT NULL)", name: "chk_membership_exactly_one_member"
      t.check_constraint "member_group_id != collection_id", name: "chk_membership_no_self_reference"
      t.foreign_key :directory_collections, column: :collection_id, on_delete: :cascade
      t.foreign_key :directory_people, column: :member_person_id, on_delete: :cascade
      t.foreign_key :directory_collections, column: :member_group_id, on_delete: :cascade
      t.foreign_key :identities, column: :created_by_identity_id, on_delete: :nullify
    end

    execute <<~SQL
      CREATE UNIQUE INDEX idx_membership_person_unique
        ON directory_memberships (collection_id, member_person_id)
        NULLS NOT DISTINCT
    SQL

    execute <<~SQL
      CREATE UNIQUE INDEX idx_membership_group_unique
        ON directory_memberships (collection_id, member_group_id)
        NULLS NOT DISTINCT
    SQL

    create_table :directory_grants, id: :bigint do |t|
      t.bigint :grantee_group_id, null: false
      t.bigint :target_collection_id, null: false
      t.string :permission, null: false
      t.boolean :recursive, default: false, null: false
      t.bigint :created_by_identity_id
      t.datetime :created_at, null: false

      t.index [:grantee_group_id, :target_collection_id, :permission], unique: true, name: "idx_grants_unique"
      t.check_constraint "permission IN ('view', 'manage_members', 'expose')", name: "chk_grant_permission"
      t.foreign_key :directory_collections, column: :grantee_group_id, on_delete: :cascade
      t.foreign_key :directory_collections, column: :target_collection_id, on_delete: :cascade
      t.foreign_key :identities, column: :created_by_identity_id, on_delete: :nullify
    end

    create_table :directory_closure, primary_key: [:ancestor_id, :descendant_id] do |t|
      t.bigint :ancestor_id, null: false
      t.bigint :descendant_id, null: false
      t.integer :depth, null: false

      t.foreign_key :directory_collections, column: :ancestor_id, on_delete: :cascade
      t.foreign_key :directory_collections, column: :descendant_id, on_delete: :cascade
    end

    create_table :directory_effective_memberships, primary_key: [:collection_id, :person_id] do |t|
      t.bigint :collection_id, null: false
      t.bigint :person_id, null: false

      t.index :person_id
      t.foreign_key :directory_collections, column: :collection_id, on_delete: :cascade
      t.foreign_key :directory_people, column: :person_id, on_delete: :cascade
    end

    create_table :directory_effective_grants, primary_key: [:person_id, :target_collection_id, :permission] do |t|
      t.bigint :person_id, null: false
      t.bigint :target_collection_id, null: false
      t.string :permission, null: false

      t.foreign_key :directory_people, column: :person_id, on_delete: :cascade
      t.foreign_key :directory_collections, column: :target_collection_id, on_delete: :cascade
    end

    create_table :directory_membership_changes, id: :bigint do |t|
      t.bigint :collection_id, null: false
      t.bigint :person_id, null: false
      t.string :op, null: false
      t.text :cause
      t.datetime :created_at, null: false

      t.index :created_at
      t.check_constraint "op IN ('added', 'removed')", name: "chk_membership_change_op"
    end
  end

  def down
    drop_table :directory_membership_changes, if_exists: true
    drop_table :directory_effective_grants, if_exists: true
    drop_table :directory_effective_memberships, if_exists: true
    drop_table :directory_closure, if_exists: true
    drop_table :directory_grants, if_exists: true
    drop_table :directory_memberships, if_exists: true
    drop_table :directory_collections, if_exists: true
    drop_table :directory_people, if_exists: true
    remove_column :backend_users, :directory_services_admin
  end
end
