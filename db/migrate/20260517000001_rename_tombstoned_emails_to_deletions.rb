# frozen_string_literal: true

class RenameTombstonedEmailsToDeletions < ActiveRecord::Migration[8.0]
  def up
    if table_exists?(:tombstoned_emails)
      rename_table :tombstoned_emails, :deletions
      rename_column :deletions, :email_digest, :email_hash
    else
      create_table :deletions do |t|
        t.string :email_hash, null: false
        t.index :email_hash, unique: true
      end
    end

    add_column :deletions, :name_combos, :text, array: true, default: []
    add_column :deletions, :session_ips, :text, array: true, default: []
    add_column :deletions, :privacy_request_reference, :text
    add_timestamps :deletions, default: -> { "CURRENT_TIMESTAMP" }

    add_index :deletions, :name_combos, using: :gin
  end

  def down
    remove_index :deletions, :name_combos
    remove_column :deletions, :name_combos
    remove_column :deletions, :session_ips
    remove_column :deletions, :privacy_request_reference
    remove_timestamps :deletions

    rename_column :deletions, :email_hash, :email_digest
    rename_table :deletions, :tombstoned_emails
  end
end
