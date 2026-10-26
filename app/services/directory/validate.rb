# frozen_string_literal: true

module Directory
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
      drop_temp_tables # clean slate
      compute_expected
      mismatches = {
        "directory_closure" => diff_closure,
        "directory_effective_memberships" => diff_effective_memberships,
        "directory_effective_grants" => diff_effective_grants
      }
      Result.new(mismatches:)
    ensure
      drop_temp_tables
    end

    private

    def compute_expected
      @conn.execute(<<~SQL)
        CREATE TEMP TABLE _expected_closure AS
        WITH RECURSIVE closure(ancestor_id, descendant_id, depth) AS (
          SELECT id, id, 0
          FROM directory_collections
          UNION ALL
          SELECT c.ancestor_id, m.member_group_id, c.depth + 1
          FROM closure c
          INNER JOIN directory_memberships m ON m.collection_id = c.descendant_id
          WHERE m.member_group_id IS NOT NULL
            AND c.depth < #{Directory::MAX_DEPTH}
        )
        SELECT DISTINCT ancestor_id, descendant_id, min(depth) AS depth
        FROM closure
        GROUP BY ancestor_id, descendant_id
      SQL

      @conn.execute(<<~SQL)
        CREATE TEMP TABLE _expected_em AS
        SELECT DISTINCT c.ancestor_id AS collection_id, m.member_person_id AS person_id
        FROM directory_memberships m
        INNER JOIN _expected_closure c ON c.descendant_id = m.collection_id
        WHERE m.member_person_id IS NOT NULL
      SQL

      @conn.execute(<<~SQL)
        CREATE TEMP TABLE _expected_eg AS
        SELECT DISTINCT em.person_id,
               CASE WHEN g.recursive THEN expanded.descendant_id ELSE g.target_collection_id END AS target_collection_id,
               g.permission
        FROM directory_grants g
        INNER JOIN _expected_em em ON em.collection_id = g.grantee_group_id
        LEFT JOIN LATERAL (
          SELECT cl.descendant_id
          FROM _expected_closure cl
          WHERE cl.ancestor_id = g.target_collection_id
            AND g.recursive = true
            AND (
              cl.descendant_id = g.target_collection_id
              OR NOT EXISTS (
                SELECT 1 FROM directory_collections dc
                WHERE dc.id = cl.descendant_id AND dc.protected = true
              )
            )
        ) expanded ON g.recursive = true
        WHERE g.recursive = false
           OR expanded.descendant_id IS NOT NULL
      SQL
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
