# frozen_string_literal: true

class CreateAhoyEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :ahoy_events do |t|
      t.references :visit, foreign_key: { to_table: :ahoy_visits }, null: true

      # Privacy: No user_id column - anonymous tracking only

      t.string :name
      t.jsonb :properties
      t.datetime :time
    end

    add_index :ahoy_events, :name
    add_index :ahoy_events, :time
    add_index :ahoy_events, [ :name, :time ]
    add_index :ahoy_events, :properties, using: :gin
  end
end
