# frozen_string_literal: true

class CreateTombstonedEmails < ActiveRecord::Migration[8.0]
  def change
    create_table :tombstoned_emails do |t|
      t.string :email_digest, null: false
      t.index :email_digest, unique: true
    end
  end
end
