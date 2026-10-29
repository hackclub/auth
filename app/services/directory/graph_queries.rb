# frozen_string_literal: true

# Shared SQL for computing the directory's derived tables (closure,
# effective memberships, effective grants). Used by both Rebuild (which
# writes the production tables) and Validate (which diffs against them).
# Keeping one copy prevents the two from diverging.
module Directory
  module GraphQueries
    module_function

    # Compute the transitive closure of group-nesting edges.
    # closure_table: the temp table to create
    # on_commit_drop: whether to add ON COMMIT DROP (Rebuild runs inside
    #   a transaction that commits; Validate drops tables in an ensure block)
    def create_closure(conn, table: "_closure", on_commit_drop: false)
      drop_clause = on_commit_drop ? "ON COMMIT DROP" : ""
      conn.execute(<<~SQL)
        CREATE TEMP TABLE #{table} #{drop_clause} AS
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
    end

    # Flatten person memberships through the closure.
    # closure_table: the temp table produced by create_closure
    def create_effective_memberships(conn, table: "_em", closure_table: "_closure", on_commit_drop: false)
      drop_clause = on_commit_drop ? "ON COMMIT DROP" : ""
      conn.execute(<<~SQL)
        CREATE TEMP TABLE #{table} #{drop_clause} AS
        SELECT DISTINCT c.ancestor_id AS collection_id, m.member_person_id AS person_id
        FROM directory_memberships m
        INNER JOIN #{closure_table} c ON c.descendant_id = m.collection_id
        WHERE m.member_person_id IS NOT NULL
      SQL
    end

    # Expand grants through group nesting, respecting recursive and protected.
    # em_table: the temp table produced by create_effective_memberships
    def create_effective_grants(conn, table: "_eg", em_table: "_em", on_commit_drop: false)
      drop_clause = on_commit_drop ? "ON COMMIT DROP" : ""
      conn.execute(<<~SQL)
        CREATE TEMP TABLE #{table} #{drop_clause} AS
        WITH RECURSIVE grant_targets AS (
          SELECT g.id AS grant_id, g.target_collection_id AS collection_id, g.permission,
                 g.grantee_group_id, 0 AS depth
          FROM directory_grants g
          UNION ALL
          SELECT gt.grant_id, m.member_group_id, gt.permission, gt.grantee_group_id,
                 gt.depth + 1
          FROM grant_targets gt
          INNER JOIN directory_grants g2 ON g2.id = gt.grant_id
          INNER JOIN directory_memberships m ON m.collection_id = gt.collection_id
          WHERE m.member_group_id IS NOT NULL
            AND g2.recursive = true
            AND gt.depth < #{Directory::MAX_DEPTH}
            AND NOT EXISTS (
              SELECT 1 FROM directory_collections dc
              WHERE dc.id = m.member_group_id AND dc.protected = true
            )
        )
        SELECT DISTINCT em.person_id, gt.collection_id AS target_collection_id, gt.permission
        FROM grant_targets gt
        INNER JOIN #{em_table} em ON em.collection_id = gt.grantee_group_id
      SQL
    end
  end
end
