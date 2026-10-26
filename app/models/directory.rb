module Directory
  def self.table_name_prefix = "directory_"

  MAX_DEPTH = 6

  # Wrap every directory write: opens a transaction, takes the advisory lock
  # (so validations like cycle/depth run under serialization), yields, then rebuilds.
  def self.mutate!(cause:, &block)
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{Rebuild::LOCK_KEY})")
      yield
      Rebuild.call(cause: cause)
    end
  end
end
