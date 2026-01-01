class AddEmailChangeSecurityEnhancements < ActiveRecord::Migration[8.0]
  def change
    # Add columns for tracking verification IPs (forensic logging)
    add_column :identity_email_change_requests, :old_email_verified_from_ip, :string
    add_column :identity_email_change_requests, :new_email_verified_from_ip, :string

    # Add step-up action binding to sessions
    add_column :identity_sessions, :last_step_up_action, :string

    # Add partial unique index to prevent concurrent pending requests per identity
    # Note: Using a function-based approach since expires_at comparison needs current time
    # This index ensures at most one non-completed, non-cancelled request per identity
    add_index :identity_email_change_requests,
              :identity_id,
              unique: true,
              where: "completed_at IS NULL AND cancelled_at IS NULL",
              name: "idx_unique_pending_email_change_per_identity"
  end
end
