class AddMissingIndexesToIdentitySessions < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  # session_token_bidx is looked up on every authenticated request and has never
  # been indexed. expires_at is in every scope. Concurrent so this doesn't lock
  # the table on deploy.
  def change
    add_index :identity_sessions, :session_token_bidx, algorithm: :concurrently
    add_index :identity_sessions, :expires_at, algorithm: :concurrently
  end
end
