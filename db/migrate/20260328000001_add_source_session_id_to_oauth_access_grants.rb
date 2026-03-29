class AddSourceSessionIdToOAuthAccessGrants < ActiveRecord::Migration[8.0]
  def change
    add_column :oauth_access_grants, :source_session_id, :bigint
    add_foreign_key :oauth_access_grants, :identity_sessions, column: :source_session_id, on_delete: :nullify
  end
end
