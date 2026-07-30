class AddBrowserSessionToIdentitySessions < ActiveRecord::Migration[8.0]
  def change
    # Nullable on purpose: existing sessions are adopted lazily on their next
    # request (SessionsHelper#current_browser_session) so nobody gets logged out.
    add_column :identity_sessions, :browser_session_id, :bigint
    add_column :identity_sessions, :revoked_reason, :string

    add_index :identity_sessions, :browser_session_id
    add_foreign_key :identity_sessions, :browser_sessions,
      column: :browser_session_id, on_delete: :nullify
  end
end
