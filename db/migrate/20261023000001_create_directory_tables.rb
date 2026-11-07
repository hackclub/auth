# frozen_string_literal: true

class CreateDirectoryTables < ActiveRecord::Migration[8.0]
  def up
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
      t.boolean :confirm_destroy, default: false, null: false
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
      t.index :member_person_id, where: "member_person_id IS NOT NULL"
      t.index :member_group_id, where: "member_group_id IS NOT NULL"
      t.foreign_key :directory_collections, column: :collection_id, on_delete: :cascade
      t.foreign_key :directory_people, column: :member_person_id, on_delete: :cascade
      t.foreign_key :directory_collections, column: :member_group_id, on_delete: :cascade
      t.foreign_key :identities, column: :created_by_identity_id, on_delete: :nullify
    end

    execute <<~SQL
      CREATE UNIQUE INDEX idx_membership_person_unique
        ON directory_memberships (collection_id, member_person_id)
        WHERE member_person_id IS NOT NULL
    SQL

    execute <<~SQL
      CREATE UNIQUE INDEX idx_membership_group_unique
        ON directory_memberships (collection_id, member_group_id)
        WHERE member_group_id IS NOT NULL
    SQL

    create_table :directory_grants, id: :bigint do |t|
      t.bigint :grantee_group_id, null: false
      t.bigint :target_collection_id, null: false
      t.string :permission, null: false
      t.boolean :recursive, default: false, null: false
      t.bigint :created_by_identity_id
      t.datetime :created_at, null: false

      t.index [ :grantee_group_id, :target_collection_id, :permission ], unique: true, name: "idx_grants_unique"
      t.index :target_collection_id
      t.check_constraint "permission IN ('view', 'manage_members', 'expose')", name: "chk_grant_permission"
      t.foreign_key :directory_collections, column: :grantee_group_id, on_delete: :cascade
      t.foreign_key :directory_collections, column: :target_collection_id, on_delete: :cascade
      t.foreign_key :identities, column: :created_by_identity_id, on_delete: :nullify
    end

    create_table :directory_closure, primary_key: [ :ancestor_id, :descendant_id ] do |t|
      t.bigint :ancestor_id, null: false
      t.bigint :descendant_id, null: false
      t.integer :depth, null: false

      t.index :descendant_id
      t.foreign_key :directory_collections, column: :ancestor_id, on_delete: :cascade
      t.foreign_key :directory_collections, column: :descendant_id, on_delete: :cascade
    end

    create_table :directory_effective_memberships, primary_key: [ :collection_id, :person_id ] do |t|
      t.bigint :collection_id, null: false
      t.bigint :person_id, null: false
      t.datetime :expires_at

      t.index :person_id
      t.index :expires_at, where: "expires_at IS NOT NULL", name: "idx_effective_memberships_expires_at"
      t.foreign_key :directory_collections, column: :collection_id, on_delete: :cascade
      t.foreign_key :directory_people, column: :person_id, on_delete: :cascade
    end

    create_table :directory_effective_grants, primary_key: [ :person_id, :target_collection_id, :permission ] do |t|
      t.bigint :person_id, null: false
      t.bigint :target_collection_id, null: false
      t.string :permission, null: false

      t.index :target_collection_id
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

    create_table :directory_exposures do |t|
      t.references :app, null: false, foreign_key: { to_table: :oauth_applications, on_delete: :cascade }
      t.references :entitlement, null: false, foreign_key: { to_table: :directory_collections, on_delete: :cascade }
      t.text :claim_name, null: false
      t.references :created_by_identity, foreign_key: { to_table: :identities, on_delete: :nullify }
      t.timestamptz :created_at, null: false, default: -> { "now()" }

      t.index %i[app_id entitlement_id], unique: true
      t.index %i[app_id claim_name], unique: true
    end

    create_table :directory_app_requirements, id: false do |t|
      t.references :app, null: false, foreign_key: { to_table: :oauth_applications, on_delete: :cascade }
      t.references :entitlement, null: false, foreign_key: { to_table: :directory_collections, on_delete: :restrict }

      t.index %i[app_id entitlement_id], unique: true
    end

    create_table :directory_app_revokers, id: false do |t|
      t.references :app, null: false, primary_key: true, foreign_key: { to_table: :oauth_applications, on_delete: :cascade }
      t.text :adapter, null: false
      t.text :config_ciphertext, null: false
      t.boolean :enabled, null: false, default: true
      t.timestamptz :last_called_at
      t.text :last_result
    end
  end

  def down
    drop_table :directory_app_revokers, if_exists: true
    drop_table :directory_app_requirements, if_exists: true
    drop_table :directory_exposures, if_exists: true
    drop_table :directory_membership_changes, if_exists: true
    drop_table :directory_effective_grants, if_exists: true
    drop_table :directory_effective_memberships, if_exists: true
    drop_table :directory_closure, if_exists: true
    drop_table :directory_grants, if_exists: true
    drop_table :directory_memberships, if_exists: true
    drop_table :directory_collections, if_exists: true
    drop_table :directory_people, if_exists: true
  end
end
