class AddIndexOnIdentitySessionsSessionTokenBidx < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :identity_sessions, :session_token_bidx, unique: true, algorithm: :concurrently
  end
end
