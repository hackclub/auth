# frozen_string_literal: true

module Directory
  def self.table_name_prefix = "directory_"

  MAX_DEPTH = 6

  # Wrap every directory write: opens a transaction, takes the advisory lock
  # (so validations like cycle/depth run under serialization), yields, then rebuilds.
  def self.mutate!(cause:, &block)
    ActiveRecord::Base.transaction do
      conn = ActiveRecord::Base.connection
      conn.execute("SELECT pg_advisory_xact_lock(#{Rebuild::LOCK_KEY})")
      Rebuild.snapshot_old(conn)
      yield
      Rebuild.call(cause: cause, skip_snapshot: true)
    end
  end
end
