# frozen_string_literal: true

module Directory
  def self.table_name_prefix = "directory_"

  # Groups can nest up to 6 levels deep (A→B→C→D→E→F). Enforced by membership validation and the recursive CTEs.
  MAX_DEPTH = 6

  # "action:target_id by:actor_id", so causes stay grep-friendly
  def self.cause(action, target: nil, actor: nil)
    parts = [ action ]
    parts << target if target
    parts = [ parts.join(":") ]
    parts << "by:#{actor}" if actor
    parts.join(" ")
  end

  # the lock every directory write serializes on. transaction-scoped and reentrant, so it's
  # safe to take again inside mutate!
  def self.lock!
    raise "Directory.lock! needs an open transaction" unless ActiveRecord::Base.connection.transaction_open?

    ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{Rebuild::LOCK_KEY})")
  end

  # every directory write goes through here: advisory lock, snapshot, the caller's changes,
  # full rebuild, diff. the diff drives AfterChangeJob.
  def self.mutate!(cause:, &block)
    ActiveRecord::Base.transaction do
      conn = ActiveRecord::Base.connection
      lock!
      Rebuild.snapshot_old(conn)
      yield
      Rebuild.call(cause: cause, skip_lock: true, skip_snapshot: true)
    end
  end
end
