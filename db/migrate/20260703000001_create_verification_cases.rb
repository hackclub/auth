class CreateVerificationCases < ActiveRecord::Migration[8.0]
  def change
    create_table :verification_cases do |t|
      t.references :identity, null: false, foreign_key: true
      t.references :opened_by, foreign_key: { to_table: :backend_users }
      t.references :verification, foreign_key: true

      t.string :status, null: false
      t.string :document_class
      t.string :alternative_reason
      t.text :alternative_reason_details

      t.string :persona_inquiry_id
      t.text :persona_session_token
      t.jsonb :persona_signal_snapshot

      t.string :access_token
      t.datetime :access_token_expires_at
      t.datetime :access_token_used_at

      t.boolean :skip_persona, default: false, null: false

      t.string :booking_uid
      t.datetime :call_starts_at

      t.jsonb :submitted_fields, default: {}, null: false

      t.boolean :attested, default: false, null: false
      t.boolean :biometric_consent, default: false, null: false
      t.boolean :recording_consent_acknowledged, default: false, null: false

      # AASM timestamps
      t.datetime :link_sent_at
      t.datetime :docs_submitted_at
      t.datetime :call_scheduled_at
      t.datetime :call_held_at
      t.datetime :approved_at
      t.datetime :denied_at

      t.datetime :deleted_at
      t.timestamps
    end

    add_index :verification_cases, :status
    add_index :verification_cases, :deleted_at
    add_index :verification_cases, :persona_inquiry_id, unique: true, where: "persona_inquiry_id IS NOT NULL AND deleted_at IS NULL"
    add_index :verification_cases, :access_token, unique: true, where: "access_token IS NOT NULL"

    create_table :verification_case_documents do |t|
      t.references :verification_case, null: false, foreign_key: true
      t.string :document_kind, null: false
      t.string :source, null: false
      t.datetime :retention_delete_at
      t.datetime :purged_at
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :verification_case_documents, :retention_delete_at
    add_index :verification_case_documents, :deleted_at

    create_table :verification_case_comments do |t|
      t.references :verification_case, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :backend_users }
      t.text :body, null: false
      t.timestamps
    end

    create_table :verification_case_events do |t|
      t.references :verification_case, null: false, foreign_key: true
      t.string :key, null: false
      t.references :actor, polymorphic: true
      t.jsonb :data, default: {}, null: false
      t.string :ip_address
      t.string :user_agent
      t.datetime :created_at, null: false
    end

    add_column :verifications, :reviewer_id, :bigint
    add_column :verifications, :checklist, :jsonb
    add_column :verifications, :expires_at, :datetime
    add_column :verifications, :sampled_at, :datetime
    add_column :verifications, :sample_reviewer_id, :bigint

    add_foreign_key :verifications, :backend_users, column: :reviewer_id
    add_foreign_key :verifications, :backend_users, column: :sample_reviewer_id
    add_index :verifications, :reviewer_id
  end
end
