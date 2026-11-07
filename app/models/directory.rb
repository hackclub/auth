# frozen_string_literal: true

module Directory
  def self.table_name_prefix = "directory_"

  # Groups can nest up to 6 levels deep (A→B→C→D→E→F). Enforced by membership validation and the recursive CTEs.
  MAX_DEPTH = 6

  # Builds a structured cause string for the audit log. Format: "action:target_id by:actor_id"
  # Use this instead of ad-hoc string interpolation so causes are grep-friendly.
  def self.cause(action, target: nil, actor: nil)
    parts = [ action ]
    parts << target if target
    parts = [ parts.join(":") ]
    parts << "by:#{actor}" if actor
    parts.join(" ")
  end

  # Gateway for every directory write. Takes a postgres advisory lock so only one mutation
  # runs at a time, snapshots the current effective_memberships, yields for the caller's
  # changes, then does a full rebuild to recompute closure + effective tables and diff them.
  # The diff drives AfterChangeJob (revocations, webhooks). Cause is a string for the audit log.
  def self.mutate!(cause:, &block)
    ActiveRecord::Base.transaction do
      conn = ActiveRecord::Base.connection
      conn.execute("SELECT pg_advisory_xact_lock(#{Rebuild::LOCK_KEY})")
      Rebuild.snapshot_old(conn)
      yield
      Rebuild.call(cause: cause, skip_lock: true, skip_snapshot: true)
    end
  end
end
