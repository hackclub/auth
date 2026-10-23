# relationship engines vs. postgres tables for a 150-person directory

> raw research report, 2026-10-20. one of five inputs to `../README.md`.

**tl;dr:** (b). steal the vocabulary, keep it in postgres, rebuild the closure on every write inside the same transaction, and emit the SCIM diff from that rebuild. the single most useful finding: zanzibar's own answer to deep group nesting (leopard) *is* a materialized closure table fed from a changefeed, and neither spicedb nor openfga ship that part open-source — so adopting an engine would still leave you building the exact thing you're already designing, just outside your transaction boundary. details below.

---

## 1. google zanzibar (the paper)

source: https://www.usenix.org/system/files/atc19-pang.pdf (annotated: https://authzed.com/zanzibar)

**tuples.** `⟨object⟩#⟨relation⟩@⟨user⟩`, where user is either a user id or a userset `⟨object#relation⟩`. the paper's own framing of your problem: "Group memberships are an important class of ACL where the object is a group and the relation is semantically equivalent to member. Groups can contain other groups, which illustrates one of the challenges facing Zanzibar, namely that evaluating whether a user belongs to a group can entail following a long chain of nested group memberships." (§1). nesting is just `group:eng#member@group:frontend#member` — no special construct.

**userset rewrites** (§2.3.1) are per-relation functions from object id → expression tree. leaves:
- `_this` — stored tuples for `object#relation`, "including indirect ACLs referenced by usersets from the tuples" (this is what makes `group#member@group#member` transitive for free)
- `computed_userset` — same object, different relation ("viewer includes editor")
- `tuple_to_userset` — "computes a tupleset from the input object, fetches relation tuples matching the tupleset, and computes a userset from every fetched relation tuple" — the hierarchy primitive ("look up the parent folder of the document and inherit its viewers")

combined with union/intersection/exclusion. figure 1's `viewer = _this ∪ computed_userset(editor) ∪ tuple_to_userset(parent → viewer)` is the template for your "manager of group" with recursion: `manage = _this(manager) ∪ tuple_to_userset(parent → manage)`.

**check evaluation** (§3.2.3): CHECK(U, object#relation) = ∃ direct tuple ∨ ∃ tuple with userset U′ s.t. CHECK(U, U′), recursively. "This kind of 'pointer chasing' works well for most types of ACLs and groups, but can be expensive when indirect ACLs or groups are deep or wide." all leaves evaluated concurrently; subtrees cancelled once determined.

**leopard** (§3.2.4) — this is the part that matters for you. "Recursive pointer chasing during check evaluation has difficulty maintaining low latency with groups that are deeply nested or have a large number of child groups. For selected namespaces that exhibit such structure, Zanzibar handles checks using Leopard." two set types: `GROUP2GROUP(s) → {e}` ("e represents a descendent group that is directly or indirectly a sub-group of the ancestor group") and `MEMBER2GROUP(s) → {e}` ("a parent group in which the user is a direct member"). membership = `MEMBER2GROUP(U) ∩ GROUP2GROUP(G) ≠ ∅`. "Group membership can be considered as a reachability problem in a graph... Flattening group-to-group paths allows reachability to be efficiently evaluated by Leopard."

read that again: GROUP2GROUP is a closure table over the group DAG; MEMBER2GROUP is your direct `memberships` table; the intersection is your `effective_memberships`. the paper's hardest-earned optimization is option (b).

freshness: offline builder from snapshots + an incremental layer that "calls Zanzibar's Watch API to receive a temporally ordered stream of Zanzibar tuple modifications and transforms the updates into a temporally ordered stream of Leopard tuple additions, updates, and deletions... In practice, a single Zanzibar tuple addition or deletion may yield potentially tens of thousands of discrete Leopard tuple events." also §3.2.5: "Zanzibar avoids storage denormalization and relies only on normalized data (except for the cases described in §3.2.4)."

**zookies / consistency** (§2.2, §2.4): snapshot reads + external consistency via spanner truetime; the "new enemy" problem (stale ACL + new content) is solved by a content-change check returning a zookie stored with the content, and later checks being "at least as fresh" as that zookie. irrelevant to you: one writer, one database, one transaction.

**apis** (§2.4): check, read (stored tuples, no rewrites), expand (§2.4.5: "returns the effective userset... follows indirect references expressed through userset rewrite rules. The result is represented by a userset tree... Expand is crucial for our clients to reason about the complete set of users and groups that have access"), write, watch.

**performance of deep nesting:** no depth statistics or hard depth limit in the paper. leopard p50 ≈150µs / p99 ≈1ms vs check p50 3ms / p95 11ms / p99 20ms. the honest reading: pointer chasing is O(depth × fanout) serial-ish reads, and google's fix was precomputation, not a faster walk.

## 2. spicedb / authzed

schema ref: https://authzed.com/docs/spicedb/concepts/schema. recursion: https://authzed.com/docs/spicedb/modeling/recursion-and-max-depth.

your case in spicedb:

```
definition user {}

definition group {
  // the only things ever written:
  relation member:         user | group#member   // membership edge (person or group)
  relation manager:        user | group#member   // grant, recursive=true
  relation direct_manager: user | group#member   // grant, recursive=false
  relation parent:         group                 // containment edge, UPWARD

  permission membership = member                 // transitive via subject-relation
  permission manage     = manager + direct_manager + parent->_manage_inherited
  permission _manage_inherited = manager + parent->_manage_inherited
}

definition app {
  relation sees: group
  permission knows = sees
}
```

check "can U manage G": `CheckPermission(resource=group:G, permission=manage, subject=user:U)`. a grant row `(grantee=admins, manage, target=eng, recursive)` becomes `group:eng#manager@group:admins#member`.

note the wart: arrows (`->`) walk relations *forward* from the resource, so "manager of an ancestor group" needs an upward `parent` edge even though `member` already encodes the same containment downward. you'd write every group-in-group edge twice (`A#member@B#member` and `B#parent@A`). your single-edge-type model + closure table answers both directions from one row. openfga has the identical constraint ("X from Y" — https://openfga.dev/docs/modeling/parent-child).

**depth/cycles:** default `--dispatch-max-depth` 50; "SpiceDB does not have a dedicated cycle detector — the max-depth limit is what terminates such loops." why no visited-set: "Semantic paradoxes: self-referential permission sets create logical inconsistencies, especially with set operations like subtraction." recommendation is to run a check before writing to detect that the target is already reachable — i.e. you do your own DAG enforcement. load-testing guidance (https://authzed.com/docs/spicedb/ops/load-testing): "recursively relating folder objects two layers deep will not incur much of a performance penalty by itself. Recursively relating folder objects 30 layers deep is likely to incur a performance penalty."

**caveats:** `relation reader: user with ip_allowlist`, CEL expressions evaluated at check time with caller-supplied context. nothing in your model needs them.

**exclusion:** see §7.

**lookups:** `LookupSubjects(group:G, membership, user)` "will do a full path walk between an object and a subject, and will consider all valid paths"; `LookupResources(user:U, membership, group)` is "a heavy request that can cause performance problems when more than 10k results" (https://authzed.com/docs/spicedb/concepts/querying-data). fine at your size.

**watch / diffs:** Watch "monitors relationship-level changes only, not permission changes... There is no native capability to directly determine 'who gained/lost a permission'" (https://authzed.com/docs/spicedb/concepts/watch). the thing that does compute permission-set diffs is **Materialize** — `WatchPermissionSets` / `LookupPermissionSets` — and it's "Available on Dedicated only" (https://authzed.com/docs/authzed/concepts/authzed-materialize). a third-party tool, authz-proof (https://github.com/ahmed-hashim-pro/authz-proof), fills the gap by evaluating everything under old and new state and diffing — which is exactly "rebuild everything on write."

**operational cost** (https://authzed.com/docs/spicedb/concepts/datastores): separate go service, dedicated postgres ≥15 database (memdb explicitly "can NOT be used in a production setting"), schema migrations (`spicedb migrate head`), preshared-key auth, gRPC, HA only with a postgres follower + second replica. typical small footprint ~0.5–1 vCPU / 512Mi–1Gi. the real cost isn't the pod, it's the **dual write**: your rails `memberships` table (for the admin UI) and spicedb's tuples are two stores with no shared transaction, and you'd need an outbox + reconciler to keep them honest. for 20 writes/day on 150 people that's all overhead and no upside.

## 3. openfga

docs: https://openfga.dev/docs/modeling/user-groups, https://openfga.dev/docs/interacting/relationship-queries, https://openfga.dev/docs/best-practices/modeling-design-principles

```
model
  schema 1.1

type user

type group
  relations
    define member: [user, group#member]
    define manager: [user, group#member]
    define direct_manager: [user, group#member]
    define parent: [group]
    define manage: manager or direct_manager or inherited_manage from parent
    define inherited_manage: manager or inherited_manage from parent

type app
  relations
    define sees: [group]
```

"all groups U is in": `ListObjects(user:U, member, type=group)`. "all users in G": `ListUsers(object=group:G, relation=member, user_filters=[{type: user}])` — usersets "will only expand to the underlying subjects if that type is specified as the user filter" (https://openfga.dev/docs/getting-started/perform-list-users). both are bounded by `listObjectsDeadline` (3s) / `listObjectsMaxResults` (1000) and "will return the results found within the time allotted" — i.e. they can silently truncate. fine for 150 users; worth knowing they're best-effort by design.

differences from spicedb: no zookies — a coarser `HIGHER_CONSISTENCY` flag that routes to primary; conditions (CEL) instead of caveats; postgres/mysql/sqlite datastores; "contextual tuples" let you pass group claims from a token at check time instead of syncing them (https://openfga.dev/docs/best-practices/adoption-patterns). their design-principles page is actively anti-recursion where avoidable: "models with specific types and flatter hierarchies perform better," and recursion should be added "only where needed." the experimental weighted-graph check (v2) has spent the last several releases fixing correctness bugs specifically in recursive-userset/nested-group shapes (https://github.com/openfga/openfga/releases — v1.18.3 "intermittently returning false... across two or more distinct recursive TTUs"). nested groups are the hard path for these engines, not the happy path.

changes feed: `ReadChanges` returns raw tuple writes/deletes, chronologically, with continuation tokens; "does not expand the tuples. If you wrote a tuple that includes a userset... the Read Changes API will return that exact tuple" (https://openfga.dev/docs/interacting/read-tuple-changes). no permission diffs.

## 4. ory keto

https://github.com/ory/keto, https://www.ory.com/docs/keto/reference/ory-permission-language. zanzibar tuples stored in postgres/mysql/cockroach (sqlite for dev). OPL is typescript-syntax: `members: (User | SubjectSet<Group, "members">)[]`, with `includes()` and `traverse()` for inheritance. notable: global max-depth **defaults to 5**, "considered a very safe value" (https://github.com/ory/keto/commit/1e3b63f33a50a0cebf7f1ddf9001846d730b0303); expand *requires* `max-depth`; in strict mode depth exhaustion is a 422, not a deny. it is literally "zanzibar in postgres" — but it's still a separate service with the same dual-write problem and no diff API.

## 5. policy engines: oso, cedar, opa

**when a policy engine is the wrong tool:** when your questions are *enumerations* ("who is in G", "which groups is U in", "who changed since v") rather than *decisions* ("may U do X"). a directory is ~90% enumeration — claims, SCIM, admin UI. PDPs answer yes/no over data you hand them; they don't own the data or its history.

**cedar:** entities carry `parents`; the hierarchy is a DAG and `principal in Group::"x"` is transitive (https://docs.cedarpolicy.com/overview/terminology.html, https://docs.cedarpolicy.com/auth/entities-syntax.html). the caller supplies the entity slice per request; cedar computes/enforces transitive closure (`add_entities` "re-computing the transitive closure"; core has `TCComputation::{ComputeNow, EnforceAlreadyComputed, AssumeAlreadyComputed}`). instructive cautionary tale: cedar 4.11–4.13 shipped an incremental-TC regression where "a user keeps a group membership that was revoked, and `principal in Group::"..."` stays true" (https://github.com/cedar-policy/cedar/issues/2606). incremental closure maintenance is where the bugs live. at your size you don't need incremental.

**opa/rego:** groups as a data document, nesting via `graph.reachable` (https://www.openpolicyagent.org/docs/policy-reference/builtins/graph) — "safe from infinite recursion caused by cyclic dependencies." data pushed via bundles; stateless; no changefeed.

**oso:** facts + polar; and the striking quote from their own ReBAC academy chapter: *"We don't recommend using the centralized relationship model in general"* — centralize only when data scale forces it; "Build authorization around your application, not the other way around" (https://www.osohq.com/academy/relationship-based-access-control-rebac). that's an authz vendor telling you (b).

## 6. postgres-native

the DAG constraint rules out two of the four classic patterns immediately: nested sets and ltree/materialized path are tree-only (a node with two parents needs two paths) (https://dev.to/dowerdev/implementing-hierarchical-data-structures-in-postgresql-ltree-vs-adjacency-list-vs-closure-table-2jpb, https://www.ackee.agency/blog/hierarchical-models-in-postgresql). that leaves:

- **adjacency list + `WITH RECURSIVE`** — write-cheap, read cost ∝ depth×fanout; pg14+ `CYCLE` clause for safety (https://www.depesz.com/2021/02/04/waiting-for-postgresql-14-search-and-cycle-clauses/). django-postgresql-dag takes this position outright.
- **closure table** — Karwin's version is trees-only (he says so in comments: hadn't tested with DAGs — https://www.percona.com/blog/moving-subtrees-in-closure-table/). the DAG-correct incremental version is Erdogan's (https://www.codeproject.com/Articles/22824/A-Model-to-Represent-Directed-Acyclic-Graphs-DAG-o): because one (ancestor, descendant) pair can be implied by multiple paths, you can't just delete closure rows on edge removal — you need path-count or entry/exit-edge bookkeeping. the modern rails incarnation is **dag_me** (https://github.com/ClosureTree/dag_me): `_dag_edges` + `_dag_paths(ancestor_id, descendant_id, min_depth, path_count)`, BEFORE INSERT advisory lock + cycle rejection, AFTER INSERT cross-product expansion, AFTER DELETE exact `path_count` decrement, plus `rebuild!`/`validate` against CTE truth. requires pg18. notably it also ships a `:recursive_cte` mode "suited for small graphs, high mutation rates, or truth verification."

**at 50 groups / 150 users / 20 writes a day:** the closure table is ≤2,500 rows, effective memberships ≤7,500 rows, and a full rebuild is a single recursive CTE that finishes in well under a millisecond. incremental maintenance (triggers, path counts) buys you nothing and costs you the cedar/erdogan class of bugs. the "rebuild everything on write" approach is the correct choice and it also happens to be the one that gives you diffs for free.

## 7. negative permissions / exclusion

what the systems say:

- zanzibar supports it as a set op; leopard flattens **reachability**, which is monotone. you can't precompute "members of A except B" as a closure without recomputing when B changes.
- spicedb: no short-circuit — "SpiceDB must wait for the other subproblem answers" (https://authzed.com/blog/check-it-out-2); reverse lookups must "perform the equivalent of a 'reduce' operation at any intersection" (https://authzed.com/blog/acl-filtering-in-authzed); best practices: **"Make sure your schema fails closed... use negation sparingly, and phrase your schema additively"** with `public - deny` as the explicit "avoid" example (https://authzed.com/docs/spicedb/best-practices); recursion doc cites "semantic paradoxes... especially with set operations like subtraction" as the reason cycles can't be cleanly detected; precedence footgun — `a - b + c` parses as `a - (b + c)` (https://github.com/ahmed-hashim-pro/authz-proof); `permission view = viewer - view` "has no single meaning. SpiceDB accepts it, then answers max depth exceeded"; CVE-2025-64529 and CVE-2026-55866 both scoped to schemas using exclusion (https://github.com/advisories/GHSA-4vrg-r928-h5vv).
- openfga: "Relations with 'and' or 'but not' are particularly expensive to evaluate"; a `user:*` result from ListUsers "doesn't necessarily indicate that all users of that type have access, it is possible that exclusions exist"; the v2 weighted-graph checker currently *rejects* `userset_with_exclusion` shapes and falls back (v1.18.2 notes).
- adam young, "No Negative Access Rules": "It is a panic response to breaches caused by principals that have far more power than they should have... Make them part of your explicit tests after the fact" (https://adam.younglogic.com/2023/10/no-negative-access-rules/).

counter-evidence, honestly: authzed's own schema validator recommends `editor - suspended` for narrow exceptions, and their google-groups walkthrough uses a `banned` relation (https://authzed.com/blog/build-you-a-google-groups). the use case is real.

why your call is still right: (1) the one legitimate use — suspension/ban — belongs on the **person** in an IdP (account disabled), not in the group algebra; (2) exclusion makes effective membership non-monotone in edges, so "removed U from group B" can *add* U to app X's SCIM push — an audit nightmare in a system whose whole job is explaining who has access and why; (3) it breaks the closure-table trick that makes your diff cheap. keep exclusion out; if someone needs "everyone except contractors," the answer is a different group with explicit membership (a dynamic/rule group can come later, computed additively).

## 8. "who can see this relationship exists"

none of the engines model it in the graph. zanzibar: nothing. spicedb OSS: every preshared key is equivalent; `ReadRelationships` sees everything. authzed cloud/dedicated/enterprise has FGAM — per-token CEL rules over request payloads, e.g. `ReadRelationshipsRequest.relationship_filter.resource_type == "resource"` — "SpiceDB open source does not include it" (https://authzed.com/docs/authzed/concepts/restricted-api-access). openfga v1.7 has an experimental access-control store, granularity = store or module (https://openfga.dev/docs/getting-started/setup-openfga/access-control). neither can express "app X may learn group G exists iff `app:X#sees@group:G`" by consulting the graph. it is always a layer above — and in your design, the rails IdP is the only caller, so `app_groups` *is* that layer. keep it as a table.

## 9. diffs / change feeds for SCIM

- spicedb Watch, openfga ReadChanges, keto: tuple-level only, no expansion, no permission diffs. materialize does it; dedicated only.
- the Leopard incremental indexer does it internally, and the paper's "tens of thousands of Leopard tuple events" per write is the honest cost of expanding one edge change into effective-membership deltas — in your case it's a handful of rows.
- the incumbents you're replacing don't even flatten: entra "cannot read or provision users in nested groups" over SCIM; okta push groups doesn't either (https://workos.com/blog/azure-entra-nested-groups-directory-sync). pushing *effective* membership is a genuine improvement and the directory has to own the closure to do it.

the postgres approach: snapshot `effective_memberships` into a temp table, rebuild, `EXCEPT` both ways, write the deltas to an outbox table in the same transaction. that's a transactional, exactly-once changefeed for free, with the triggering write's id attached — strictly better than what any of the engines offer without a hosted add-on.

## 10. verdict + schema

**don't embed an engine.** the things an engine is good at (millions of objects, per-resource ACLs, bounded-staleness across regions, checks from many services) are absent; the things you actually need (enumeration, diffs, transactional consistency with your admin UI, visibility filtering per app) are the things the OSS engines don't do. you would run a second datastore, solve dual-write, and *still* build a closure + outbox beside it. (c) is wrong too — your model is already a clean subset of zanzibar's and that vocabulary is worth keeping (one edge type, subject-relations, named computed sets).

what to keep from zanzibar: the tuple mental model (`group#member@group#member` is just a row with a nullable fk pair), "computed usersets" as named sql views/tables rather than ad-hoc queries, and the discipline that stored edges are the only truth and everything else is derived and rebuildable. if a future app needs per-document ReBAC, that's an *app* concern — feed it effective groups the way okta/entra feed openfga today.

sketch:

```sql
create table groups (
  id bigint primary key generated always as identity,
  slug text not null unique,
  name text not null
);

-- one edge type; person XOR group
create table memberships (
  id bigint primary key generated always as identity,
  group_id bigint not null references groups on delete cascade,
  member_person_id bigint references people on delete cascade,
  member_group_id  bigint references groups on delete cascade,
  created_by_id bigint references people,
  created_at timestamptz not null default now(),
  check (num_nonnulls(member_person_id, member_group_id) = 1),
  check (member_group_id is distinct from group_id),
  unique nulls not distinct (group_id, member_person_id),
  unique nulls not distinct (group_id, member_group_id)
);

create table grants (
  id bigint primary key generated always as identity,
  grantee_group_id bigint not null references groups on delete cascade,
  target_group_id  bigint not null references groups on delete cascade,
  permission text not null check (permission in ('manage_members','manage_grants','view')),
  recursive boolean not null default true,
  unique (grantee_group_id, target_group_id, permission)
);

create table app_groups (
  app_id bigint not null references apps on delete cascade,
  group_id bigint not null references groups on delete cascade,
  claim_name text not null,
  required boolean not null default false,
  primary key (app_id, group_id)
);

-- derived: GROUP2GROUP, includes reflexive rows
create table group_closure (
  ancestor_id bigint not null references groups on delete cascade,
  descendant_id bigint not null references groups on delete cascade,
  depth int not null,
  primary key (ancestor_id, descendant_id)
);

-- derived: MEMBER2GROUP ⋈ GROUP2GROUP
create table effective_memberships (
  group_id bigint not null references groups on delete cascade,
  person_id bigint not null references people on delete cascade,
  primary key (group_id, person_id)
);
create index on effective_memberships (person_id);

-- derived: who may do what to which group
create table effective_grants (
  person_id bigint not null,
  target_group_id bigint not null,
  permission text not null,
  primary key (person_id, target_group_id, permission)
);

-- the changefeed
create table membership_changes (
  id bigint primary key generated always as identity,
  group_id bigint not null,
  person_id bigint not null,
  op text not null check (op in ('added','removed')),
  caused_by_membership_id bigint,
  created_at timestamptz not null default now()
);
```

rebuild, run inside the same transaction as every write to `memberships`/`grants` (a `Directory::Rebuild` service object, not a trigger — testable, and the diff is right there):

```sql
-- 1. cycle check for the new edge (child_group -> ... -> group_id?)
with recursive up as (
  select :group_id as g
  union
  select m.group_id from memberships m join up on m.member_group_id = up.g
) select 1 from up where g = :member_group_id;  -- any row => reject

-- 2. snapshot, rebuild closure
create temp table old_em on commit drop as table effective_memberships;
truncate group_closure, effective_memberships, effective_grants;

insert into group_closure
with recursive c(ancestor_id, descendant_id, depth) as (
  select id, id, 0 from groups
  union
  select c.ancestor_id, m.member_group_id, c.depth + 1
  from c join memberships m on m.group_id = c.descendant_id
  where m.member_group_id is not null
) select ancestor_id, descendant_id, min(depth) from c group by 1, 2;

insert into effective_memberships
select distinct c.ancestor_id, m.member_person_id
from group_closure c
join memberships m on m.group_id = c.descendant_id
where m.member_person_id is not null;

insert into effective_grants
select distinct em.person_id, c.descendant_id, g.permission
from grants g
join effective_memberships em on em.group_id = g.grantee_group_id
join group_closure c on c.ancestor_id = g.target_group_id
where g.recursive or c.depth = 0;

-- 3. diff -> outbox
insert into membership_changes (group_id, person_id, op, caused_by_membership_id)
select group_id, person_id, 'added',   :cause from (table effective_memberships except table old_em) d
union all
select group_id, person_id, 'removed', :cause from (table old_em except table effective_memberships) d;
```

the SCIM pusher consumes `membership_changes` joined to `app_groups` for apps with a provisioning target; claims at token time read `effective_memberships ⋈ app_groups`; "can U manage G" is a pk lookup on `effective_grants`. a nightly `validate` job re-runs the CTE into a temp table and diffs it against `effective_memberships` (dag_me's pattern) so drift is caught, not trusted away. if you ever outgrow full rebuild — you won't at 150, but if the community users ever creep in — the upgrade path is erdogan/dag_me incremental closure, and nothing above the derived tables changes.

Sources: [Zanzibar paper](https://www.usenix.org/system/files/atc19-pang.pdf) · [annotated Zanzibar](https://authzed.com/zanzibar) · [SpiceDB schema](https://authzed.com/docs/spicedb/concepts/schema) · [SpiceDB recursion](https://authzed.com/docs/spicedb/modeling/recursion-and-max-depth) · [SpiceDB load testing](https://authzed.com/docs/spicedb/ops/load-testing) · [SpiceDB watch](https://authzed.com/docs/spicedb/concepts/watch) · [Materialize](https://authzed.com/docs/authzed/concepts/authzed-materialize) · [SpiceDB querying](https://authzed.com/docs/spicedb/concepts/querying-data) · [SpiceDB datastores](https://authzed.com/docs/spicedb/concepts/datastores) · [SpiceDB best practices](https://authzed.com/docs/spicedb/best-practices) · [check-it-out-2](https://authzed.com/blog/check-it-out-2) · [ACL filtering](https://authzed.com/blog/acl-filtering-in-authzed) · [Restricted API access](https://authzed.com/docs/authzed/concepts/restricted-api-access) · [authz-proof](https://github.com/ahmed-hashim-pro/authz-proof) · [OpenFGA user groups](https://openfga.dev/docs/modeling/user-groups) · [OpenFGA parent-child](https://openfga.dev/docs/modeling/parent-child) · [OpenFGA queries](https://openfga.dev/docs/interacting/relationship-queries) · [OpenFGA ListUsers](https://openfga.dev/docs/getting-started/perform-list-users) · [OpenFGA ReadChanges](https://openfga.dev/docs/interacting/read-tuple-changes) · [OpenFGA design principles](https://openfga.dev/docs/best-practices/modeling-design-principles) · [OpenFGA production](https://openfga.dev/docs/best-practices/running-in-production) · [OpenFGA access control](https://openfga.dev/docs/getting-started/setup-openfga/access-control) · [OpenFGA releases](https://github.com/openfga/openfga/releases) · [Keto](https://github.com/ory/keto) · [OPL](https://www.ory.com/docs/keto/reference/ory-permission-language) · [Keto max-depth](https://github.com/ory/keto/commit/1e3b63f33a50a0cebf7f1ddf9001846d730b0303) · [Cedar terminology](https://docs.cedarpolicy.com/overview/terminology.html) · [Cedar entities](https://docs.cedarpolicy.com/auth/entities-syntax.html) · [Cedar TC regression](https://github.com/cedar-policy/cedar/issues/2606) · [OPA graph builtins](https://www.openpolicyagent.org/docs/policy-reference/builtins/graph) · [Oso ReBAC academy](https://www.osohq.com/academy/relationship-based-access-control-rebac) · [Erdogan DAG closure](https://www.codeproject.com/Articles/22824/A-Model-to-Represent-Directed-Acyclic-Graphs-DAG-o) · [Karwin closure tables](https://www.percona.com/blog/moving-subtrees-in-closure-table/) · [dag_me](https://github.com/ClosureTree/dag_me) · [ltree vs adjacency vs closure](https://dev.to/dowerdev/implementing-hierarchical-data-structures-in-postgresql-ltree-vs-adjacency-list-vs-closure-table-2jpb) · [Ackee hierarchies](https://www.ackee.agency/blog/hierarchical-models-in-postgresql) · [PG14 CYCLE](https://www.depesz.com/2021/02/04/waiting-for-postgresql-14-search-and-cycle-clauses/) · [No negative access rules](https://adam.younglogic.com/2023/10/no-negative-access-rules/) · [Entra nested groups + SCIM](https://workos.com/blog/azure-entra-nested-groups-directory-sync)
