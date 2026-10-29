# frozen_string_literal: true

module Directory
  class Rebuild
    LOCK_KEY = 8_675_309

    def self.call(cause:, skip_lock: false, skip_snapshot: false)
      new(cause:, skip_lock:, skip_snapshot:).call
    end

    def self.snapshot_old(conn)
      conn.execute("DROP TABLE IF EXISTS _old_em, _new_closure, _new_em, _new_eg")
      conn.execute(<<~SQL)
        CREATE TEMP TABLE _old_em ON COMMIT DROP AS
        SELECT collection_id, person_id
        FROM directory_effective_memberships
      SQL
    end

    def initialize(cause:, skip_lock: false, skip_snapshot: false)
      @cause = cause
      @skip_lock = skip_lock
      @skip_snapshot = skip_snapshot
      @conn = ActiveRecord::Base.connection
    end

    def call
      @conn.execute("SELECT pg_advisory_xact_lock(#{LOCK_KEY})") unless @skip_lock
      snapshot_old unless @skip_snapshot
      compute_closure
      compute_effective_memberships
      compute_effective_grants
      apply_closure_diff
      apply_membership_diff
      apply_grant_diff
      change_ids = emit_changes
      register_after_commit(change_ids) if change_ids.present?
      change_ids
    end

    private

    def snapshot_old
      self.class.snapshot_old(@conn)
    end

    def compute_closure
      GraphQueries.create_closure(@conn, table: "_new_closure", on_commit_drop: true)
    end

    def compute_effective_memberships
      GraphQueries.create_effective_memberships(@conn, table: "_new_em", closure_table: "_new_closure", on_commit_drop: true)
    end

    def compute_effective_grants
      GraphQueries.create_effective_grants(@conn, table: "_new_eg", em_table: "_new_em", on_commit_drop: true)
    end

    def apply_closure_diff
      @conn.execute(<<~SQL)
        DELETE FROM directory_closure
        WHERE NOT EXISTS (
          SELECT 1 FROM _new_closure nc
          WHERE nc.ancestor_id = directory_closure.ancestor_id
            AND nc.descendant_id = directory_closure.descendant_id
        )
      SQL

      @conn.execute(<<~SQL)
        INSERT INTO directory_closure (ancestor_id, descendant_id, depth)
        SELECT nc.ancestor_id, nc.descendant_id, nc.depth
        FROM _new_closure nc
        WHERE NOT EXISTS (
          SELECT 1 FROM directory_closure dc
          WHERE dc.ancestor_id = nc.ancestor_id
            AND dc.descendant_id = nc.descendant_id
        )
      SQL

      @conn.execute(<<~SQL)
        UPDATE directory_closure SET depth = nc.depth
        FROM _new_closure nc
        WHERE directory_closure.ancestor_id = nc.ancestor_id
          AND directory_closure.descendant_id = nc.descendant_id
          AND directory_closure.depth != nc.depth
      SQL
    end

    def apply_membership_diff
      @conn.execute(<<~SQL)
        DELETE FROM directory_effective_memberships
        WHERE NOT EXISTS (
          SELECT 1 FROM _new_em ne
          WHERE ne.collection_id = directory_effective_memberships.collection_id
            AND ne.person_id = directory_effective_memberships.person_id
        )
      SQL

      @conn.execute(<<~SQL)
        INSERT INTO directory_effective_memberships (collection_id, person_id)
        SELECT ne.collection_id, ne.person_id
        FROM _new_em ne
        WHERE NOT EXISTS (
          SELECT 1 FROM directory_effective_memberships dem
          WHERE dem.collection_id = ne.collection_id
            AND dem.person_id = ne.person_id
        )
      SQL
    end

    def apply_grant_diff
      @conn.execute(<<~SQL)
        DELETE FROM directory_effective_grants
        WHERE NOT EXISTS (
          SELECT 1 FROM _new_eg ng
          WHERE ng.person_id = directory_effective_grants.person_id
            AND ng.target_collection_id = directory_effective_grants.target_collection_id
            AND ng.permission = directory_effective_grants.permission
        )
      SQL

      @conn.execute(<<~SQL)
        INSERT INTO directory_effective_grants (person_id, target_collection_id, permission)
        SELECT ng.person_id, ng.target_collection_id, ng.permission
        FROM _new_eg ng
        WHERE NOT EXISTS (
          SELECT 1 FROM directory_effective_grants deg
          WHERE deg.person_id = ng.person_id
            AND deg.target_collection_id = ng.target_collection_id
            AND deg.permission = ng.permission
        )
      SQL
    end

    def emit_changes
      added = @conn.execute(<<~SQL)
        INSERT INTO directory_membership_changes (collection_id, person_id, op, cause, created_at)
        SELECT ne.collection_id, ne.person_id, 'added', #{@conn.quote(@cause)}, NOW()
        FROM _new_em ne
        WHERE NOT EXISTS (
          SELECT 1 FROM _old_em oe
          WHERE oe.collection_id = ne.collection_id
            AND oe.person_id = ne.person_id
        )
        RETURNING id
      SQL

      removed = @conn.execute(<<~SQL)
        INSERT INTO directory_membership_changes (collection_id, person_id, op, cause, created_at)
        SELECT oe.collection_id, oe.person_id, 'removed', #{@conn.quote(@cause)}, NOW()
        FROM _old_em oe
        WHERE NOT EXISTS (
          SELECT 1 FROM _new_em ne
          WHERE ne.collection_id = oe.collection_id
            AND ne.person_id = oe.person_id
        )
        RETURNING id
      SQL

      ids = []
      added.each { |row| ids << row["id"] }
      removed.each { |row| ids << row["id"] }
      ids
    end

    def register_after_commit(change_ids)
      ids = change_ids.dup
      # Pre-resolve revocation data while entities still exist (before commit might cascade-delete them)
      revocations = pre_resolve_revocations(ids)
      @conn.current_transaction.after_commit do
        Directory::AfterChangeJob.perform_later(change_ids: ids, revocations: revocations)
      end
    end

    def pre_resolve_revocations(change_ids)
      rows = @conn.exec_query(
        ActiveRecord::Base.sanitize_sql_array([
          "SELECT mc.person_id, mc.collection_id FROM directory_membership_changes mc WHERE mc.id IN (?) AND mc.op = 'removed'",
          change_ids
        ])
      )

      revocations = []
      rows.each do |row|
        person = Directory::Person.find_by(id: row["person_id"])
        collection = Directory::Collection.find_by(id: row["collection_id"])
        next unless person && collection&.entitlement?

        app_ids = (
          Directory::Exposure.where(entitlement_id: collection.id).pluck(:app_id) +
          Directory::AppRequirement.where(entitlement_id: collection.id).pluck(:app_id)
        ).uniq
        next if app_ids.empty?

        revocations << { identity_id: person.identity_id, email: person.primary_email, app_ids: app_ids }
      end
      revocations
    end
  end
end
