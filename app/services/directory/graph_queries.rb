# frozen_string_literal: true

# Shared SQL for computing the directory's derived tables (closure,
# effective memberships, effective grants). Used by both Rebuild (which
# writes the production tables) and Validate (which diffs against them).
# Keeping one copy prevents the two from diverging.
module Directory
  # Raw SQL for computing derived tables. Shared by Rebuild (production writes)
  # and Validate (read-only drift check) so the two can't diverge.
  module GraphQueries
    module_function

    # Recursive CTE that walks group-nesting edges to produce every (ancestor, descendant, depth)
    # triple. Self-loops included (depth 0). Used to flatten "person in A, A nested in B" into
    # "person is effective member of both A and B."
    ACTIVE_MEMBERSHIP = "(m.expires_at IS NULL OR m.expires_at > NOW())"

    def create_closure(conn, table: "_closure", on_commit_drop: false)
      drop_clause = on_commit_drop ? "ON COMMIT DROP" : ""
      conn.execute(<<~SQL)
        CREATE TEMP TABLE #{table} #{drop_clause} AS
        WITH RECURSIVE closure(ancestor_id, descendant_id, depth, path_expires_at) AS (
          SELECT id, id, 0, NULL::timestamptz
          FROM directory_collections
          UNION ALL
          SELECT c.ancestor_id, m.member_group_id, c.depth + 1,
                 CASE WHEN c.path_expires_at IS NULL THEN m.expires_at
                      WHEN m.expires_at IS NULL THEN c.path_expires_at
                      ELSE LEAST(c.path_expires_at, m.expires_at) END
          FROM closure c
          INNER JOIN directory_memberships m ON m.collection_id = c.descendant_id
          WHERE m.member_group_id IS NOT NULL
            AND #{ACTIVE_MEMBERSHIP}
            AND c.depth < #{Directory::MAX_DEPTH}
        )
        SELECT ancestor_id, descendant_id, min(depth) AS depth,
               CASE WHEN bool_or(path_expires_at IS NULL) THEN NULL
                    ELSE MAX(path_expires_at) END AS path_expires_at
        FROM closure
        GROUP BY ancestor_id, descendant_id
      SQL
    end

    # Joins direct person→collection memberships through the closure to produce every
    # (collection, person) pair where the person is an effective member — directly or via nesting.
    def create_effective_memberships(conn, table: "_em", closure_table: "_closure", on_commit_drop: false)
      drop_clause = on_commit_drop ? "ON COMMIT DROP" : ""
      conn.execute(<<~SQL)
        CREATE TEMP TABLE #{table} #{drop_clause} AS
        SELECT collection_id, person_id,
               CASE WHEN bool_or(path_expires_at IS NULL) THEN NULL
                    ELSE MAX(path_expires_at) END AS expires_at
        FROM (
          SELECT c.ancestor_id AS collection_id, m.member_person_id AS person_id,
                 CASE WHEN c.path_expires_at IS NULL THEN m.expires_at
                      WHEN m.expires_at IS NULL THEN c.path_expires_at
                      ELSE LEAST(c.path_expires_at, m.expires_at) END AS path_expires_at
          FROM directory_memberships m
          INNER JOIN #{closure_table} c ON c.descendant_id = m.collection_id
          WHERE m.member_person_id IS NOT NULL
            AND #{ACTIVE_MEMBERSHIP}
        ) raw
        GROUP BY collection_id, person_id
      SQL
    end

    # Recursive CTE that walks grants down through nested groups. A grant on collection X with
    # recursive=true expands to X's child groups (and their children, etc.), stopping at
    # collections marked protected=true. The result is (person, target_collection, permission)
    # for every person in the grantee group.
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
            AND #{ACTIVE_MEMBERSHIP}
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
