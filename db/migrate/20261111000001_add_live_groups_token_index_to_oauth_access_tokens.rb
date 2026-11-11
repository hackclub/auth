class AddLiveGroupsTokenIndexToOAuthAccessTokens < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  # directory claim reach asks "does this app have any live token issued with groups?" per
  # exposure; without this it scans every token the app ever issued
  def change
    add_index :oauth_access_tokens, :application_id,
      name: "index_oauth_access_tokens_live_groups_by_application",
      where: "revoked_at IS NULL AND (' ' || scopes || ' ' LIKE '% groups %')",
      algorithm: :concurrently
  end
end
