# frozen_string_literal: true

class CreateIdentityTombstoneCollisions < ActiveRecord::Migration[8.0]
  def change
    create_table :identity_tombstone_collisions do |t|
      t.references :identity, null: false, foreign_key: true
      t.references :deletion, null: false, foreign_key: true
      t.timestamps
    end

    add_index :identity_tombstone_collisions, [:identity_id, :deletion_id], unique: true, name: "idx_tombstone_collisions_uniqueness"
  end
end
