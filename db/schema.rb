# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_10_14_152131) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.string "encryption_key"
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "activities", force: :cascade do |t|
    t.string "trackable_type"
    t.bigint "trackable_id"
    t.string "owner_type"
    t.bigint "owner_id"
    t.string "key"
    t.text "parameters"
    t.string "recipient_type"
    t.bigint "recipient_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id", "owner_type"], name: "index_activities_on_owner_id_and_owner_type"
    t.index ["owner_type", "owner_id"], name: "index_activities_on_owner"
    t.index ["recipient_id", "recipient_type"], name: "index_activities_on_recipient_id_and_recipient_type"
    t.index ["recipient_type", "recipient_id"], name: "index_activities_on_recipient"
    t.index ["trackable_id", "trackable_type"], name: "index_activities_on_trackable_id_and_trackable_type"
    t.index ["trackable_type", "trackable_id"], name: "index_activities_on_trackable"
  end

  create_table "addresses", force: :cascade do |t|
    t.string "first_name"
    t.string "last_name"
    t.string "line_1"
    t.string "line_2"
    t.string "city"
    t.string "state"
    t.string "postal_code"
    t.integer "country"
    t.bigint "identity_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["identity_id"], name: "index_addresses_on_identity_id"
  end

  create_table "audits1984_audits", force: :cascade do |t|
    t.integer "status", default: 0, null: false
    t.text "notes"
    t.bigint "session_id", null: false
    t.bigint "auditor_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["auditor_id"], name: "index_audits1984_audits_on_auditor_id"
    t.index ["session_id"], name: "index_audits1984_audits_on_session_id"
  end

  create_table "backend_organizer_positions", force: :cascade do |t|
    t.bigint "program_id", null: false
    t.bigint "backend_user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["backend_user_id"], name: "index_backend_organizer_positions_on_backend_user_id"
    t.index ["program_id"], name: "index_backend_organizer_positions_on_program_id"
  end

  create_table "backend_users", force: :cascade do |t|
    t.string "slack_id"
    t.string "username"
    t.string "icon_url"
    t.boolean "super_admin"
    t.boolean "program_manager"
    t.boolean "all_fields_access"
    t.boolean "manual_document_verifier"
    t.boolean "human_endorser"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "active"
    t.string "credential_id"
    t.boolean "can_break_glass"
    t.index ["slack_id"], name: "index_backend_users_on_slack_id"
  end

  create_table "break_glass_records", force: :cascade do |t|
    t.bigint "backend_user_id", null: false
    t.bigint "break_glassable_id", null: false
    t.text "reason", null: false
    t.datetime "accessed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "automatic", default: false
    t.string "break_glassable_type", null: false
    t.index ["backend_user_id", "break_glassable_id", "accessed_at"], name: "idx_on_backend_user_id_break_glassable_id_accessed__e06f302c56"
    t.index ["backend_user_id"], name: "index_break_glass_records_on_backend_user_id"
    t.index ["break_glassable_id", "break_glassable_type"], name: "idx_on_break_glassable_id_break_glassable_type_14e1e3ce71"
    t.index ["break_glassable_id"], name: "index_break_glass_records_on_break_glassable_id"
  end

  create_table "console1984_commands", force: :cascade do |t|
    t.text "statements"
    t.bigint "sensitive_access_id"
    t.bigint "session_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sensitive_access_id"], name: "index_console1984_commands_on_sensitive_access_id"
    t.index ["session_id", "created_at", "sensitive_access_id"], name: "on_session_and_sensitive_chronologically"
  end

  create_table "console1984_sensitive_accesses", force: :cascade do |t|
    t.text "justification"
    t.bigint "session_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["session_id"], name: "index_console1984_sensitive_accesses_on_session_id"
  end

  create_table "console1984_sessions", force: :cascade do |t|
    t.text "reason"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_console1984_sessions_on_created_at"
    t.index ["user_id", "created_at"], name: "index_console1984_sessions_on_user_id_and_created_at"
  end

  create_table "console1984_users", force: :cascade do |t|
    t.string "username", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["username"], name: "index_console1984_users_on_username"
  end

  create_table "flipper_features", force: :cascade do |t|
    t.string "key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_flipper_features_on_key", unique: true
  end

  create_table "flipper_gates", force: :cascade do |t|
    t.string "feature_key", null: false
    t.string "key", null: false
    t.text "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["feature_key", "key", "value"], name: "index_flipper_gates_on_feature_key_and_key_and_value", unique: true
  end

  create_table "good_job_batches", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "description"
    t.jsonb "serialized_properties"
    t.text "on_finish"
    t.text "on_success"
    t.text "on_discard"
    t.text "callback_queue_name"
    t.integer "callback_priority"
    t.datetime "enqueued_at"
    t.datetime "discarded_at"
    t.datetime "finished_at"
    t.datetime "jobs_finished_at"
  end

  create_table "good_job_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "active_job_id", null: false
    t.text "job_class"
    t.text "queue_name"
    t.jsonb "serialized_params"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.text "error"
    t.integer "error_event", limit: 2
    t.text "error_backtrace", array: true
    t.uuid "process_id"
    t.interval "duration"
    t.index ["active_job_id", "created_at"], name: "index_good_job_executions_on_active_job_id_and_created_at"
    t.index ["process_id", "created_at"], name: "index_good_job_executions_on_process_id_and_created_at"
  end

  create_table "good_job_processes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "state"
    t.integer "lock_type", limit: 2
  end

  create_table "good_job_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "key"
    t.jsonb "value"
    t.index ["key"], name: "index_good_job_settings_on_key", unique: true
  end

  create_table "good_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "queue_name"
    t.integer "priority"
    t.jsonb "serialized_params"
    t.datetime "scheduled_at"
    t.datetime "performed_at"
    t.datetime "finished_at"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "active_job_id"
    t.text "concurrency_key"
    t.text "cron_key"
    t.uuid "retried_good_job_id"
    t.datetime "cron_at"
    t.uuid "batch_id"
    t.uuid "batch_callback_id"
    t.boolean "is_discrete"
    t.integer "executions_count"
    t.text "job_class"
    t.integer "error_event", limit: 2
    t.text "labels", array: true
    t.uuid "locked_by_id"
    t.datetime "locked_at"
    t.index ["active_job_id", "created_at"], name: "index_good_jobs_on_active_job_id_and_created_at"
    t.index ["batch_callback_id"], name: "index_good_jobs_on_batch_callback_id", where: "(batch_callback_id IS NOT NULL)"
    t.index ["batch_id"], name: "index_good_jobs_on_batch_id", where: "(batch_id IS NOT NULL)"
    t.index ["concurrency_key", "created_at"], name: "index_good_jobs_on_concurrency_key_and_created_at"
    t.index ["concurrency_key"], name: "index_good_jobs_on_concurrency_key_when_unfinished", where: "(finished_at IS NULL)"
    t.index ["cron_key", "created_at"], name: "index_good_jobs_on_cron_key_and_created_at_cond", where: "(cron_key IS NOT NULL)"
    t.index ["cron_key", "cron_at"], name: "index_good_jobs_on_cron_key_and_cron_at_cond", unique: true, where: "(cron_key IS NOT NULL)"
    t.index ["finished_at"], name: "index_good_jobs_jobs_on_finished_at", where: "((retried_good_job_id IS NULL) AND (finished_at IS NOT NULL))"
    t.index ["labels"], name: "index_good_jobs_on_labels", where: "(labels IS NOT NULL)", using: :gin
    t.index ["locked_by_id"], name: "index_good_jobs_on_locked_by_id", where: "(locked_by_id IS NOT NULL)"
    t.index ["priority", "created_at"], name: "index_good_job_jobs_for_candidate_lookup", where: "(finished_at IS NULL)"
    t.index ["priority", "created_at"], name: "index_good_jobs_jobs_on_priority_created_at_when_unfinished", order: { priority: "DESC NULLS LAST" }, where: "(finished_at IS NULL)"
    t.index ["priority", "scheduled_at"], name: "index_good_jobs_on_priority_scheduled_at_unfinished_unlocked", where: "((finished_at IS NULL) AND (locked_by_id IS NULL))"
    t.index ["queue_name", "scheduled_at"], name: "index_good_jobs_on_queue_name_and_scheduled_at", where: "(finished_at IS NULL)"
    t.index ["scheduled_at"], name: "index_good_jobs_on_scheduled_at", where: "(finished_at IS NULL)"
  end

  create_table "identities", force: :cascade do |t|
    t.string "first_name"
    t.string "last_name"
    t.date "birthday"
    t.string "legal_first_name"
    t.string "legal_last_name"
    t.string "primary_email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "country"
    t.string "slack_id"
    t.boolean "ysws_eligible"
    t.bigint "primary_address_id"
    t.datetime "deleted_at"
    t.text "aadhaar_number_ciphertext"
    t.string "aadhaar_number_bidx"
    t.boolean "hq_override", default: false
    t.boolean "came_in_through_adult_program", default: false
    t.string "phone_number"
    t.boolean "permabanned", default: false
    t.datetime "locked_at"
    t.boolean "use_two_factor_authentication"
    t.datetime "legacy_migrated_at"
    t.string "onboarding_scenario"
    t.integer "promote_click_count", default: 0
    t.boolean "developer_mode", default: false, null: false
    t.index ["aadhaar_number_bidx"], name: "index_identities_on_aadhaar_number_bidx", unique: true
    t.index ["deleted_at"], name: "index_identities_on_deleted_at"
    t.index ["legacy_migrated_at"], name: "index_identities_on_legacy_migrated_at"
    t.index ["primary_address_id"], name: "index_identities_on_primary_address_id"
    t.index ["slack_id"], name: "index_identities_on_slack_id"
  end

  create_table "identity_aadhaar_records", force: :cascade do |t|
    t.bigint "identity_id", null: false
    t.datetime "deleted_at"
    t.text "raw_json_response"
    t.date "date_of_birth"
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["identity_id"], name: "index_identity_aadhaar_records_on_identity_id"
  end

  create_table "identity_backup_codes", force: :cascade do |t|
    t.string "aasm_state", default: "previewed", null: false
    t.text "code_digest", null: false
    t.bigint "identity_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["identity_id"], name: "index_identity_backup_codes_on_identity_id"
  end

  create_table "identity_documents", force: :cascade do |t|
    t.integer "document_type"
    t.bigint "identity_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.index ["deleted_at"], name: "index_identity_documents_on_deleted_at"
    t.index ["identity_id"], name: "index_identity_documents_on_identity_id"
  end

  create_table "identity_login_codes", force: :cascade do |t|
    t.datetime "expires_at"
    t.string "token_bidx"
    t.text "token_ciphertext"
    t.datetime "used_at"
    t.bigint "identity_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "return_url"
    t.index ["identity_id"], name: "index_identity_login_codes_on_identity_id"
  end

  create_table "identity_resemblances", force: :cascade do |t|
    t.bigint "identity_id", null: false
    t.bigint "past_identity_id", null: false
    t.string "type"
    t.bigint "document_id"
    t.bigint "past_document_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["document_id"], name: "index_identity_resemblances_on_document_id"
    t.index ["identity_id"], name: "index_identity_resemblances_on_identity_id"
    t.index ["past_document_id"], name: "index_identity_resemblances_on_past_document_id"
    t.index ["past_identity_id"], name: "index_identity_resemblances_on_past_identity_id"
  end

  create_table "identity_sessions", force: :cascade do |t|
    t.string "device_info"
    t.datetime "expires_at"
    t.string "fingerprint"
    t.string "ip"
    t.datetime "last_seen"
    t.decimal "latitude"
    t.decimal "longitude"
    t.string "os_info"
    t.string "session_token_bidx"
    t.text "session_token_ciphertext"
    t.datetime "signed_out_at"
    t.string "timezone"
    t.bigint "identity_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["identity_id"], name: "index_identity_sessions_on_identity_id"
  end

  create_table "identity_totps", force: :cascade do |t|
    t.string "aasm_state"
    t.datetime "deleted_at"
    t.datetime "last_used_at"
    t.text "secret_ciphertext"
    t.bigint "identity_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["identity_id"], name: "index_identity_totps_on_identity_id"
  end

  create_table "identity_v2_login_codes", force: :cascade do |t|
    t.text "code"
    t.inet "ip_address"
    t.datetime "used_at"
    t.text "user_agent"
    t.bigint "identity_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "login_attempt_id"
    t.index ["identity_id", "login_attempt_id", "code", "used_at"], name: "index_v2_codes_on_identity_attempt_code_used"
    t.index ["identity_id"], name: "index_identity_v2_login_codes_on_identity_id"
    t.index ["login_attempt_id"], name: "index_identity_v2_login_codes_on_login_attempt_id"
  end

  create_table "login_attempts", force: :cascade do |t|
    t.bigint "identity_id", null: false
    t.bigint "session_id"
    t.string "aasm_state"
    t.jsonb "authentication_factors"
    t.text "browser_token_ciphertext"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "provenance"
    t.string "next_action"
    t.index ["identity_id"], name: "index_login_attempts_on_identity_id"
    t.index ["session_id"], name: "index_login_attempts_on_session_id"
  end

  create_table "oauth_access_grants", force: :cascade do |t|
    t.bigint "resource_owner_id", null: false
    t.bigint "application_id", null: false
    t.string "token", null: false
    t.integer "expires_in", null: false
    t.text "redirect_uri", null: false
    t.string "scopes", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "revoked_at"
    t.string "resource_owner_type", null: false
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["resource_owner_id", "resource_owner_type"], name: "polymorphic_owner_oauth_access_grants"
    t.index ["resource_owner_id"], name: "index_oauth_access_grants_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
  end

  create_table "oauth_access_tokens", force: :cascade do |t|
    t.bigint "resource_owner_id"
    t.bigint "application_id", null: false
    t.string "refresh_token"
    t.integer "expires_in"
    t.string "scopes"
    t.datetime "created_at", null: false
    t.datetime "revoked_at"
    t.string "previous_refresh_token", default: "", null: false
    t.string "resource_owner_type"
    t.text "token_ciphertext"
    t.string "token_bidx"
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource_owner_id", "resource_owner_type"], name: "polymorphic_owner_oauth_access_tokens"
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["token_bidx"], name: "index_oauth_access_tokens_on_token_bidx", unique: true
  end

  create_table "oauth_applications", force: :cascade do |t|
    t.string "name", null: false
    t.string "uid", null: false
    t.string "secret", null: false
    t.text "redirect_uri", null: false
    t.string "scopes", default: "", null: false
    t.boolean "confidential", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "program_key_bidx"
    t.text "program_key_ciphertext"
    t.boolean "active", default: true
    t.integer "trust_level", default: 0, null: false
    t.bigint "owner_identity_id"
    t.index ["owner_identity_id"], name: "index_oauth_applications_on_owner_identity_id"
    t.index ["program_key_bidx"], name: "index_oauth_applications_on_program_key_bidx", unique: true
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
  end

  create_table "settings", force: :cascade do |t|
    t.string "key", null: false
    t.text "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "verifications", force: :cascade do |t|
    t.bigint "identity_id", null: false
    t.bigint "identity_document_id"
    t.string "status", null: false
    t.string "rejection_reason"
    t.string "rejection_reason_details"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.string "type"
    t.boolean "fatal", default: false, null: false
    t.string "aadhaar_hc_transaction_id"
    t.string "aadhaar_external_transaction_id"
    t.string "aadhaar_link"
    t.bigint "aadhaar_record_id"
    t.string "issues", default: [], array: true
    t.datetime "pending_at"
    t.datetime "ignored_at"
    t.string "ignored_reason"
    t.datetime "approved_at"
    t.datetime "rejected_at"
    t.text "internal_rejection_comment"
    t.index ["aadhaar_record_id"], name: "index_verifications_on_aadhaar_record_id"
    t.index ["deleted_at"], name: "index_verifications_on_deleted_at"
    t.index ["fatal"], name: "index_verifications_on_fatal"
    t.index ["identity_document_id"], name: "index_verifications_on_identity_document_id"
    t.index ["identity_id"], name: "index_verifications_on_identity_id"
    t.index ["type"], name: "index_verifications_on_type"
  end

  create_table "versions", force: :cascade do |t|
    t.string "whodunnit"
    t.datetime "created_at"
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.string "event", null: false
    t.text "object"
    t.jsonb "object_changes"
    t.jsonb "extra_data"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "addresses", "identities"
  add_foreign_key "backend_organizer_positions", "backend_users"
  add_foreign_key "backend_organizer_positions", "oauth_applications", column: "program_id"
  add_foreign_key "break_glass_records", "backend_users"
  add_foreign_key "identities", "addresses", column: "primary_address_id"
  add_foreign_key "identity_aadhaar_records", "identities"
  add_foreign_key "identity_backup_codes", "identities"
  add_foreign_key "identity_documents", "identities"
  add_foreign_key "identity_login_codes", "identities"
  add_foreign_key "identity_resemblances", "identities"
  add_foreign_key "identity_resemblances", "identities", column: "past_identity_id"
  add_foreign_key "identity_resemblances", "identity_documents", column: "document_id"
  add_foreign_key "identity_resemblances", "identity_documents", column: "past_document_id"
  add_foreign_key "identity_sessions", "identities"
  add_foreign_key "identity_totps", "identities"
  add_foreign_key "identity_v2_login_codes", "identities"
  add_foreign_key "identity_v2_login_codes", "login_attempts"
  add_foreign_key "login_attempts", "identities"
  add_foreign_key "login_attempts", "identity_sessions", column: "session_id"
  add_foreign_key "oauth_access_grants", "identities", column: "resource_owner_id"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "identities", column: "resource_owner_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "verifications", "identities"
  add_foreign_key "verifications", "identity_aadhaar_records", column: "aadhaar_record_id"
  add_foreign_key "verifications", "identity_documents"
end
