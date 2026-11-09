# frozen_string_literal: true

class CreateSAMLCertificates < ActiveRecord::Migration[8.0]
  def change
    create_table :saml_certificates do |t|
      t.string :role, null: false, default: "rollover"
      t.text :certificate, null: false
      t.string :key_path, null: false
      t.string :fingerprint, null: false
      t.datetime :expires_at, null: false
      t.datetime :signing_at
      t.datetime :retired_at

      t.timestamps
    end

    add_index :saml_certificates, :role
    add_index :saml_certificates, :fingerprint, unique: true
  end
end
