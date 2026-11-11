class AddLiveGroupsTokenIndexToOAuthAccessTokens < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  NAME = "index_oauth_access_tokens_live_groups_by_application"

  # directory claim reach asks "does this app have any live token issued with groups?" per
  # exposure; without this it scans every token the app ever issued
  def up
    # a concurrent build that dies part way (lock timeout, killed deploy) leaves an INVALID
    # index under this name, which if_not_exists would happily keep. drop that and rebuild.
    if index_name_exists?(:oauth_access_tokens, NAME) && !valid_index?
      remove_index :oauth_access_tokens, name: NAME, algorithm: :concurrently
    end

    add_index :oauth_access_tokens, :application_id,
      name: NAME,
      where: "revoked_at IS NULL AND (' ' || scopes || ' ' LIKE '% groups %')",
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :oauth_access_tokens, name: NAME, algorithm: :concurrently, if_exists: true
  end

  private

  def valid_index?
    select_value(<<~SQL)
      SELECT i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE c.relname = #{connection.quote(NAME)}
    SQL
  end
end
