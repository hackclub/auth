class AddMissingIndexesToIdentitySessions < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  # session_token_bidx is looked up on every authenticated request and has never
  # been indexed. expires_at is in every scope. Concurrent so this doesn't lock
  # the table on deploy.
  # if_not_exists because a concurrent build that fails leaves an INVALID index
  # behind, and the retry would then collide with it.
  def change
    add_index :identity_sessions, :session_token_bidx, algorithm: :concurrently, if_not_exists: true
    add_index :identity_sessions, :expires_at, algorithm: :concurrently, if_not_exists: true
  end
end
