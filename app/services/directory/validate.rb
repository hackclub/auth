# frozen_string_literal: true

module Directory
  # Drift detector: recomputes all derived tables from scratch (using the same GraphQueries
  # as Rebuild) and diffs them against the live tables. Returns mismatches per table.
  # Used by the /directory/health page to verify the rebuild hasn't diverged from truth.
  class Validate
    Result = Struct.new(:mismatches, keyword_init: true) do
      def valid? = mismatches.values.all? { |v| v[:missing].empty? && v[:extra].empty? }
    end

    def self.call
      new.call
    end

    def initialize
      @conn = ActiveRecord::Base.connection
    end

    def call
      ActiveRecord::Base.transaction do
        @conn.execute("SELECT pg_advisory_xact_lock(#{Directory::Rebuild::LOCK_KEY})")
        drop_temp_tables # clean slate
        compute_expected
        mismatches = {
          "directory_closure" => diff_closure,
          "directory_effective_memberships" => diff_effective_memberships,
          "directory_effective_grants" => diff_effective_grants
        }
        Result.new(mismatches:)
      end
    ensure
      drop_temp_tables
    end

    private

    def compute_expected
      GraphQueries.create_closure(@conn, table: "_expected_closure", on_commit_drop: true)
      GraphQueries.create_effective_memberships(@conn, table: "_expected_em", closure_table: "_expected_closure", on_commit_drop: true)
      GraphQueries.create_effective_grants(@conn, table: "_expected_eg", em_table: "_expected_em", on_commit_drop: true)
    end

    def diff_closure
      missing = @conn.execute(<<~SQL).to_a
        SELECT ec.ancestor_id, ec.descendant_id, ec.depth
        FROM _expected_closure ec
        WHERE NOT EXISTS (
          SELECT 1 FROM directory_closure dc
          WHERE dc.ancestor_id = ec.ancestor_id
            AND dc.descendant_id = ec.descendant_id
        )
      SQL

      extra = @conn.execute(<<~SQL).to_a
        SELECT dc.ancestor_id, dc.descendant_id, dc.depth
        FROM directory_closure dc
        WHERE NOT EXISTS (
          SELECT 1 FROM _expected_closure ec
          WHERE ec.ancestor_id = dc.ancestor_id
            AND ec.descendant_id = dc.descendant_id
        )
      SQL

      { missing:, extra: }
    end

    def diff_effective_memberships
      missing = @conn.execute(<<~SQL).to_a
        SELECT ee.collection_id, ee.person_id
        FROM _expected_em ee
        WHERE NOT EXISTS (
          SELECT 1 FROM directory_effective_memberships dem
          WHERE dem.collection_id = ee.collection_id
            AND dem.person_id = ee.person_id
        )
      SQL

      extra = @conn.execute(<<~SQL).to_a
        SELECT dem.collection_id, dem.person_id
        FROM directory_effective_memberships dem
        WHERE NOT EXISTS (
          SELECT 1 FROM _expected_em ee
          WHERE ee.collection_id = dem.collection_id
            AND ee.person_id = dem.person_id
        )
      SQL

      { missing:, extra: }
    end

    def diff_effective_grants
      missing = @conn.execute(<<~SQL).to_a
        SELECT ee.person_id, ee.target_collection_id, ee.permission
        FROM _expected_eg ee
        WHERE NOT EXISTS (
          SELECT 1 FROM directory_effective_grants deg
          WHERE deg.person_id = ee.person_id
            AND deg.target_collection_id = ee.target_collection_id
            AND deg.permission = ee.permission
        )
      SQL

      extra = @conn.execute(<<~SQL).to_a
        SELECT deg.person_id, deg.target_collection_id, deg.permission
        FROM directory_effective_grants deg
        WHERE NOT EXISTS (
          SELECT 1 FROM _expected_eg ee
          WHERE ee.person_id = deg.person_id
            AND ee.target_collection_id = deg.target_collection_id
            AND ee.permission = deg.permission
        )
      SQL

      { missing:, extra: }
    end

    def drop_temp_tables
      %w[_expected_closure _expected_em _expected_eg].each do |t|
        @conn.execute("DROP TABLE IF EXISTS #{t}")
      end
    end
  end
end
