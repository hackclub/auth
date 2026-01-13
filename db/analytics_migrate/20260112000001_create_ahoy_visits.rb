# frozen_string_literal: true

class CreateAhoyVisits < ActiveRecord::Migration[8.0]
  def change
    create_table :ahoy_visits do |t|
      t.string :visit_token
      t.string :visitor_token

      # Privacy: No user_id column - anonymous tracking only

      # Request info (privacy-safe - IPs are masked)
      t.string :ip
      t.text :user_agent
      t.text :referrer
      t.string :referring_domain

      # Landing page
      t.text :landing_page

      # Technology (derived from user agent)
      t.string :browser
      t.string :os
      t.string :device_type

      # UTM parameters (for campaign tracking)
      t.string :utm_source
      t.string :utm_medium
      t.string :utm_campaign
      t.string :utm_term
      t.string :utm_content

      t.datetime :started_at
    end

    add_index :ahoy_visits, :visit_token, unique: true
    add_index :ahoy_visits, :visitor_token
    add_index :ahoy_visits, :started_at
  end
end
