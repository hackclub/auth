# frozen_string_literal: true

require "rails_helper"

RSpec.describe Directory::Exposure do
  it "answers 'any live groups token for this app?' from the partial index, not a scan of the app's tokens" do
    sql = "EXPLAIN SELECT 1 FROM oauth_access_tokens WHERE oauth_access_tokens.application_id = 1 " \
      "AND oauth_access_tokens.revoked_at IS NULL AND #{format(described_class::REQUESTS_GROUPS_SQL, 'oauth_access_tokens.scopes')}"

    # with seq scans off the planner uses the index whenever its predicate matches the query's,
    # which is the thing to prove; on a near-empty table it would otherwise pick a scan anyway
    ActiveRecord::Base.connection.execute("SET LOCAL enable_seqscan = off")
    plan = ActiveRecord::Base.connection.select_values(sql).join("\n")

    expect(plan).to include("index_oauth_access_tokens_live_groups_by_application")
  end
end
