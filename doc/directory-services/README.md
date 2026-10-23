# directory services: research & recommendation

> 2026-10-20. synthesis of five research passes (in `research/`) measured against the model we sketched in conversation. this is a design input, not a spec. open decisions are at the bottom.

## tl;dr

the model we sketched is right in its bones. three findings from the research change its details, and the rest of what's worth taking from the field is in "what we're stealing, and from whom" below:

1. **groups need a `kind`: `role` or `entitlement`.** people and roles nest into roles; roles nest into entitlements; entitlements are terminal and are the only thing an app may be told about. this is active directory's AGDLP pattern with the replication nonsense stripped off. what it buys, precisely: the manager of an entitlement can only ever grant that one entitlement. entitlements can't be a back door into roles (which would let a low-stakes manager mint role members) or chain into other entitlements. it does *not* stop an authorized person from nesting "all staff" into "prod deployers"; that's a policy call by whoever holds manage-members on prod deployers, and the guardrail there is who holds that grant plus a loud UI. it also matches the vocabulary you used unprompted — "YSWS Docs Access" and "1Password Users" are entitlements, "Fulltimers" and "Gap Year" are roles.
2. **the directory boundary must be structural.** a `directory_people` row that community identities simply don't have. not a flag, not a WHERE clause. every product that used a flag (entra guests, google unmanaged accounts) spent a decade mopping up enumeration leaks.
3. **rebuild the closure on every write, inside the transaction, and diff it.** the diff is the SCIM changefeed. zanzibar's own fix for deep nesting is a materialized closure table fed from a changefeed, and the open-source engines don't ship that part. we'd be building it anyway. build it where the transaction is.

the two things nobody else does and we're doing anyway: exposure-to-apps as a permissioned act on the group (every vendor configures it app-side), and a single `app_groups` edge driving assignment, claims, and SCIM scope (only jumpcloud does this; okta and entra split it into three settings and that's where their bugs live). both are defensible. the first needs a two-sided approval flow or app onboarding stalls.

## the model

### one account table; the directory is a structurally separate subset

`identities` stays the account table for everyone (50k). the directory is `directory_people(identity_id)` plus the graph. a community identity has no `directory_people` row and therefore cannot appear in a membership, a grant, an LDAP entry, or a SCIM push. "in the directory" is a join, not a predicate someone forgets.

evidence: entra B2B guests are the same object type as members with one `userType` attribute, and every dynamic rule, picker, and enumeration path has to remember the filter. trustedsec enumerated a tenant's users and groups through default guest access and microsoft said "not technically a bug." google verified-domain consumer accounts become "unmanaged" then "conflicting" and the fix is a transfer tool. the products that handle two populations cleanly all do it with a hard boundary: separate forest (AD), separate realm (keycloak), separate org (zitadel), separate tenant (entra external ID), separate product (okta/auth0). the one place two-systems loses is staff who are also community members: keycloak realms make a person exist twice. one account table with an optional directory row handles that. it's auth0 organizations' shape and atlassian's portal-only-customer shape.

promotion and offboarding fall out: creating the row brings a person in; deleting it cascades memberships, which rebuilds the closure, which emits removals, which deprovisions every SCIM target. one delete.

### groups have a `kind`

```
kind = role         -- a fact about people. fulltimers, gap year, special little dudes.
kind = entitlement  -- a fact about access. ysws docs access, 1password users, slack-hq.
```

nesting matrix:

| member ↓ / group → | role | entitlement |
|---|---|---|
| person | yes | yes (the "add random people" case) |
| role | yes | yes (fulltimers ⇒ docs access) |
| entitlement | **no** | **no** |

entitlements are terminal. only entitlements may appear in `app_groups`. three check constraints.

why: the AD research surfaced the real reason AGDLP persists. it was sold as a replication optimization, but in single-domain shops it survived because group scope makes it *physically impossible* to nest a resource group inside a role group. be precise about what that prevents, because it's easy to overclaim (the first draft of this doc did). it does **not** prevent "all staff ⊂ prod deployers": that's role→entitlement, the allowed direction, and the trimarc case study (a department nested into Domain Admins, "fewer than 10 intended admins, almost 150 actual") is the same allowed direction. the only thing standing between an org and that edge is who holds `manage_members` on the entitlement and whether the UI says "this adds 150 people."

what the flavors *do* prevent is escalation through the back door. if entitlements could sit inside roles, then gap year, holding manage-members on docs access, could add a random person to docs access and thereby make them a fulltimer, and thereby a member of every entitlement fulltimers feeds. a one-group grant becomes "mint fulltimers." if entitlements could sit inside entitlements, docs access inside 1password users means gap year hands out 1password. with entitlements terminal, **the manager of an entitlement can only ever grant that one entitlement.** role managers are different: adding someone to a role grants everything the role implies, which is inherent to what a role is, and is why roles need tighter management and `protected` exists.

the second thing the flavors buy: apps can only ever be told about entitlements, so "what does slack know" is always a deliberately named access grant and never an org-chart node by accident. google arrived at a similar place from the other direction: one Group object serving as mailing list, drive principal, IAM principal and security group produced latacora's "gripes" post and an irreversible `security` label with a four-kind nesting matrix. type it now; it can't be retrofitted.

cost: every app exposure requires an entitlement group to exist. "assert fulltimers to slack" becomes "slack-hq entitlement, fulltimers is a member." more rows, and that's the point: the entitlement is where direct adds live, where the claim name lives, and where the SCIM target hangs.

### memberships: one edge type, a DAG, no cycles

```
memberships(group_id, member_person_id | member_group_id, created_by, expires_at?, created_at)
```

a person in a group and a group in a group are the same row. the edge belongs to the group, not the member. kanidm's design note on this is worth keeping verbatim: "there is a security benefit to the relationship of 'groups have members' rather than 'users are members of groups'. that benefit is delegated administration" — authorizing a write against the group means a manager of one group can only ever add people to that one group.

direction, named in the schema not the docs: a member's members are transitively members of `group_id`; grants on `group_id` cover them. github's parent/child naming confused people on launch day because "parent inherits child's permissions" and "child inherits parent's grants" are the same fact read from opposite ends.

cycles: reject at write with a recursive CTE. AD and kanidm tolerate cycles via fixpoint; authentik had cycles pegging a worker at 100% CPU until 2023. forbidding is simpler and nobody defends a cycle as intentional. add a depth cap (4 is generous for 150 people) so the UI can always show the path.

`expires_at` is google's best idea: membership with a built-in end. a sweeper writes the removal through the same rebuild path so it's indistinguishable from a manual remove.

what we are not building: OUs. google's OU/group duality is the single most confusing thing in the survey; okta's realms and entra's administrative units are both "we needed an admin-scoping container and didn't want it to be a group." a recursive grant on a parent role *is* OU-scoped delegation without a second hierarchy. one encoding of membership, ever: AD's `primaryGroupID`, added in 2000 for a replication limit that went away in 2003, still silently breaks entra connect today. that's the argument against letting `is_in_workspace` or any slack-side state be a shadow membership next to the real one.

### effective_memberships: materialized, rebuilt per write, diffed

```
group_closure(ancestor_id, descendant_id, depth)      -- GROUP2GROUP, reflexive
effective_memberships(group_id, person_id)            -- MEMBER2GROUP ⋈ closure
effective_grants(person_id, target_group_id, permission)
membership_changes(group_id, person_id, op, caused_by, created_at)   -- the outbox
```

on every write to `memberships` or `grants`: snapshot `effective_memberships` to a temp table, truncate and rebuild all three derived tables with one recursive CTE, `EXCEPT` both ways into `membership_changes`. same transaction. a service object, not a trigger, so it's testable and the diff is right there. nightly, re-run the CTE into a temp table and compare, so drift is caught rather than trusted away.

this is the only thing any consumer reads. tokens, saml assertions, the ldap projection, scim scope, the admin UI's "can you see this page" check. entra's whole class of "nesting works for tokens but not for provisioning or licensing" bugs comes from subsystems walking the graph differently. we have one table; never let a second path exist.

evidence that materializing is right: AD computes closure per query and the result is `LDAP_MATCHING_RULE_IN_CHAIN` being ripped out of checkmk as "incredibly slow"; 389-ds's memberOf plugin triggered 14M internal searches for 400 nested groups; sssd's `id` is slow for the same reason; openldap deprecated write-time memberof for read-time dynlist, hit the performance wall, and un-deprecated it. zanzibar's leopard index is GROUP2GROUP ∩ MEMBER2GROUP, i.e. exactly these tables. incremental closure maintenance is where the bugs live (cedar 4.11–4.13 shipped a regression where revoked group memberships stayed true); at our size full rebuild is sub-millisecond and buys correctness for free. if we ever outgrow it, the upgrade is a path-counting closure table (erdogan / dag_me) and nothing above the derived tables changes.

### grants: a ledger, with a vocabulary and a protected flag

```
grants(grantee_group_id, target_group_id, permission, recursive)
permission ∈ { view, manage_members, manage_group, manage_grants, expose }
```

- `view`: see the group and its members in the directory UI.
- `manage_members`: add/remove direct members. the 90% case. freeipa's `memberManager` and kanidm's `entry_managed_by` are exactly this and nothing more.
- `manage_group`: rename, describe, delete, change `kind`/`protected`.
- `manage_grants`: hand out grants on the target. this is AD's `WriteDacl`, the escalation primitive. kanidm splits "manage members" from "change who manages" into different builtin admin groups for this reason. default `recursive=false`, and consider not allowing recursive at all.
- `expose`: create `app_groups` rows for the target. needed so a directory admin can hold it recursively on a root role and onboard apps without N managers acting.

`recursive` means "also every group reachable from the target via member edges" (sub-groups). it does not and cannot reach *upward* to entitlements the target feeds into, because that's the other direction of the walk. this is why one edge type works: admin flows toward members, membership flows toward groups, the walks never cross.

no deny. keycloak's FGAP v2 needed explicit denies because its tree forced over-granting, and the first bug was a scope that didn't alias through a deny. in a DAG with multiple paths, denies are where the holes come from. if a grant is too broad, make a narrower group.

`protected` on groups: ineligible as the target of a *recursive* grant; only direct grants reach it. this is AdminSDHolder without the hourly cron. AD's answer to "helpdesk has reset-password on OU=Staff, a domain admin lives in OU=Staff" was a reconciliation loop that stamps a template ACL on protected objects every 60 minutes and silently undoes your delegation. ours is a column checked at evaluation. the day someone nests Admins under Staff for convenience, the recursive grant on Staff stops at the protected boundary.

escalation rule to document and enforce: adding group A as a member of group B means "B trusts A's managers." whoever writes that edge must hold `manage_members` on B. the UI should say so in words.

the point of all of this being tables: `SELECT * FROM grants` is the delegation ledger AD never had. bloodhound is a ten-year industry because that table didn't exist.

### app_groups: exposure is a grant, and it's two-sided

```
app_groups(app_id, group_id, claim_name, status, requested_by, approved_by, approved_at)
  -- group must be kind=entitlement
app_requirements(app_id, group_id)   -- "must be in this group to log in at all"
```

this is the one place the model is genuinely novel. every surveyed product configures exposure on the app side: okta app admin by name-regex, entra enterprise-app owner, google super admin picking ≤75 names, keycloak client mappers, authentik scope mappings, kanidm claim maps by oauth2 admins, AD by "whatever the bind account can read" which is everything. the closest cousin is entra entitlement management, where resource owners contribute groups into a catalog and package managers compose from it — a two-sided grant, still admin-driven.

ours: an app learns a group exists only via an approved `app_groups` row. the token for app X contains exactly the `claim_name`s for X's rows intersected with the user's effective memberships. no "list groups" endpoint. no wildcard. the app never sees our group names. this structurally eliminates the overage cliff (okta: token refused above 100 groups per claim; entra: claim silently vanishes above 150/200 and teleport's RBAC stopped matching for half a fleet) and it's microsoft's own "send app roles, not groups, so the app has its own vocabulary" advice made mandatory.

the inversion has a cost and a risk. cost: onboarding an app needs the group's manager to act, not one admin; mitigated by `expose` held recursively by directory admins. risk: a group manager exposing a sensitive group to a community-created app is the consent-phishing shape. so it's two-sided: the app's owner *requests* `(group, claim_name)`, someone holding `expose` on the group *approves*. and `oauth_applications.trust_level` already exists to gate this: `hq_official` apps can be approved by any `expose` holder; `community_*` apps require a directory admin. changing `claim_name` or adding a requirement re-opens approval, the way slack re-prompts on scope change.

`required` is pulled into its own table because the AD/ADFS lesson is that "must be in G to sign in" and "emit G as a claim" live on different lifecycles and are owned by different people (security vs app team). it follows nesting because it reads `effective_memberships`, which is better than entra's assignment-required (direct members only, AADSTS50105 for everyone else). decide explicitly whether directory admins bypass it. entra's global admins do, silently. recommend: no bypass, loud log.

### things deliberately left out

- **exclusion / negative membership.** spicedb's best-practices page: "phrase your schema additively"; two CVEs scoped to schemas using exclusion; openfga's new checker rejects exclusion shapes and falls back. exclusion makes effective membership non-monotone in edges, so removing someone from group B can *add* them to app X's SCIM push. the one legitimate use, suspension, belongs on the identity not in the group algebra. "everyone except contractors" is a different group with explicit members.
- **dynamic / rule-based groups.** not now. if later, as a rule that *writes* memberships (okta/onelogin style) so `effective_memberships` stays the only truth, never as read-time evaluation (entra: 24h+ processing tails and a "pause all groups" script; google: dynamic groups can't nest or have owners).
- **OUs.** covered above. the recursive grant is the OU.
- **community "facts" as groups.** community identities have attributes on `identities` and claims derived from them in the existing doorkeeper config. the directory doesn't know they exist.

## protocols are adapters over one table

| protocol | reads | notes |
|---|---|---|
| **oidc** | `effective_memberships ⋈ app_groups[app]` → `groups: [claim_name...]` behind a `groups` scope | doorkeeper `normal_claim` with the application in scope. `app_requirements` enforced at authorize time |
| **saml** | same slice → `<Attribute Name="groups">` or per-SP attribute format | replaces `allowed_emails:` in `config/saml.yml` with a requirement row. `allowed_attributes:` stays, it's attribute-level |
| **ldap** (later) | read-only projection. flat `ou=people` + `ou=groups` under one suffix; `member` direct, `memberOf` transitive; `groupOfNames` + auxiliary `posixGroup`; uuid RDNs | kanidm / lldap shape. kanidm's stated reason: "almost all clients can use filters for entry selection." bind account = an app, sees its `app_groups` slice only. authelia's default group mode searches `(member={dn})` so emit both directions. serve empty groups despite RFC 4519's MUST |
| **scim** (outbound, directory) | `membership_changes ⋈ app_groups` for apps with a scim target; nightly full reconcile against the target | push *effective* membership with RFC 7643 `type: indirect`. push group objects only for `app_groups` edges, never the whole closure (the entra→scim bug). idempotent PATCH, never okta's "push now" full overwrite. deactivate, don't delete |

### slack grid is not this

the existing `SCIMService` provisions every identity who logs in to slack, keyed off onboarding scenario, during the saml flow. that's account-level provisioning for the 50k, not group-driven provisioning for the 150. it stays where it is (rename to `Slack::Scim` for honesty), shares an http client with the directory reconciler at most, and does not inherit from it. one more reason: slack grid has *two* group systems (IdP groups from SCIM, user groups from admins) with no bridge, and SCIM rate limits are shared org-wide across all SCIM apps. if the directory later wants to drive slack IdP groups for staff, that's a scim target like any other, writing to the IdP-group side only.

## what we're stealing, and from whom

| idea | from | where it lands |
|---|---|---|
| role / entitlement split enforced by type, bounding entitlement managers to one group | AD (AGDLP), google (security groups + nesting matrix) | `groups.kind` + check constraints |
| edge lives on the group, authorize against the group | kanidm, AD linked attributes | `memberships(group_id, …)`; policy checks target group only |
| server-computed transitive closure as the only membership API | AD `tokenGroups`, zanzibar leopard | `effective_memberships` |
| one edge drives assignment + claims + scim scope | jumpcloud | `app_groups` |
| per-app vocabulary, never directory names | entra app roles | `app_groups.claim_name` |
| resource owner contributes, app side composes | entra entitlement management, github app approval, slack scope re-approval | `app_groups.status` + `expose` |
| "manage members" ≠ "manage who manages" | kanidm `entry_managed_by` vs `idm_access_control_admins`, freeipa `memberManager` | `manage_members` vs `manage_grants` |
| protected principals escape inherited delegation | AD AdminSDHolder, kanidm `idm_high_privilege`, okta admin-role groups | `groups.protected` |
| can't grant what you don't hold | discord manage-roles | policy on `manage_grants` |
| membership expiry | google cloud identity | `memberships.expires_at` |
| stable opaque ids, never names as keys | AD SIDs / objectGUID vs DNs | ids everywhere; LDAP uuid RDNs |
| "required to log in" as prior art | entra assignment-required, okta app assignment, slack required workspaces, zitadel check-authorization | `app_requirements`, nesting-aware |
| hard population boundary | AD forests, keycloak realms, zitadel orgs, atlassian portal-only, google visitors | `directory_people` |
| rebuild + validate against CTE truth | dag_me | nightly drift check |

## what they got wrong, briefly

| product | the wound |
|---|---|
| **AD** | OU tree carries name + policy + delegation at once; group scope as a user-visible type; two membership encodings; `memberOf` lies (primary group, nesting, cross-domain); ACLs with no ledger; full closure in every ticket (1015-group hard cap); no notion of which apps may see a group |
| **entra** | nesting transitive for tokens, not for assignment/provisioning/licensing; claim overage drops the claim entirely; four group types; admin units delegate properties not members; dynamic groups 24h+ |
| **okta** | no nesting; one team = three groups (assign, push, claim regex); 100-group claim cap refuses the token; group owners own nothing |
| **google** | OU vs group duality; groups admin can't be OU-scoped; transitive APIs paywalled; 75-name saml mapping breaks on rename; consumer/workspace namespace collision |
| **keycloak** | groups tree + roles DAG + client roles, nobody knows which to use; realms are a hard wall even when you need staff in two places; FGAP v2's first bug was a deny that didn't alias |
| **authentik** | `parent_id` tree with inverted semantics (children are members of parents); cycles pegged CPU; no-bound-users means sync *everyone* |
| **openldap** | three group classes, MUST member so no empty groups, memberOf not in the schema, project flip-flopped on write-time vs read-time |
| **github** | shipped nested teams then made CODEOWNERS and review requests ignore the hierarchy |
| **slack grid** | IdP groups and user groups, two systems, no bridge, org-wide SCIM rate limit |
| **atlassian** | flat groups "won't do" because the big IdPs don't nest; a group per product role eats licenses |
| **zanzibar engines** | nested groups are the hard path; diffs and visibility are paid tiers; dual-write with your own db |

## mapping onto this repo

what exists and what it becomes:

- **`identities`** stays the account table. `directory_people(identity_id)` is new.
- **`oauth_applications`** (`Program`) is the app table. `trust_level` gates exposure approval. `organizers` / `program_collaborators` are who may *request* exposure for an app.
- **saml SPs in `config/saml.yml`** need to become rows (or a `saml_service_providers` table keyed to an app) so `app_groups` has something to point at. `allowed_emails:` → an `app_requirements` row on an entitlement. `allowed_attributes:` stays.
- **doorkeeper claims** in `config/initializers/doorkeeper_openid_connect.rb` gain a `groups` claim behind a `groups` scope. the `normal_claim` block gets the application so it can filter. nothing else there changes; `ysws_eligible` and friends are community facts and stay as they are.
- **`slack_idp_groups`**: zero references in app, lib, config, or `internal/`. came in with flavortown onboarding. drop it, or repurpose the shape as `scim_links(app_id, group_id|person_id, external_id)` for the reconciler.
- **`SCIMService`** → `Slack::Scim`. untouched otherwise. the directory gets `Directory::Scim::{Target, Client, Reconciler}`.
- **`backend_users`** is out of scope. it's the admin console's own user table, not "who works here." later its boolean roles could become grants, but that's a refactor nothing here depends on.

## proposed schema

```sql
create table directory_people (
  id            bigint primary key generated always as identity,
  identity_id   bigint not null unique references identities,
  created_at    timestamptz not null default now()
);

create table directory_groups (
  id            bigint primary key generated always as identity,
  slug          text not null unique,
  name          text not null,
  kind          text not null check (kind in ('role','entitlement')),
  protected     boolean not null default false,
  description   text,
  created_by_id bigint references directory_people,
  created_at    timestamptz not null default now()
);

-- one edge type; person XOR group; the edge belongs to group_id
create table directory_memberships (
  id               bigint primary key generated always as identity,
  group_id         bigint not null references directory_groups on delete cascade,
  member_person_id bigint references directory_people on delete cascade,
  member_group_id  bigint references directory_groups on delete cascade,
  created_by_id    bigint references directory_people,
  expires_at       timestamptz,
  created_at       timestamptz not null default now(),
  check (num_nonnulls(member_person_id, member_group_id) = 1),
  check (member_group_id is distinct from group_id),
  unique nulls not distinct (group_id, member_person_id),
  unique nulls not distinct (group_id, member_group_id)
);
-- app-level validations (or triggers): member_group.kind = 'role'; no cycle; depth <= 4

create table directory_grants (
  id               bigint primary key generated always as identity,
  grantee_group_id bigint not null references directory_groups on delete cascade,
  target_group_id  bigint not null references directory_groups on delete cascade,
  permission       text not null check (permission in ('view','manage_members','manage_group','manage_grants','expose')),
  recursive        boolean not null default false,
  created_by_id    bigint references directory_people,
  created_at       timestamptz not null default now(),
  unique (grantee_group_id, target_group_id, permission)
);
-- app-level: recursive grants never reach protected targets; manage_grants recursive discouraged

create table directory_app_groups (
  id            bigint primary key generated always as identity,
  app_id        bigint not null references oauth_applications on delete cascade,
  group_id      bigint not null references directory_groups on delete cascade,  -- kind = entitlement
  claim_name    text not null,
  status        text not null default 'requested' check (status in ('requested','approved','revoked')),
  requested_by_id bigint references identities,
  approved_by_id  bigint references directory_people,
  approved_at   timestamptz,
  unique (app_id, group_id),
  unique (app_id, claim_name)
);

create table directory_app_requirements (
  app_id   bigint not null references oauth_applications on delete cascade,
  group_id bigint not null references directory_groups on delete cascade,
  primary key (app_id, group_id)
);

-- derived; truncated and rebuilt in the same transaction as any write above
create table directory_group_closure (
  ancestor_id   bigint not null references directory_groups on delete cascade,
  descendant_id bigint not null references directory_groups on delete cascade,
  depth         int not null,
  primary key (ancestor_id, descendant_id)
);

create table directory_effective_memberships (
  group_id  bigint not null references directory_groups on delete cascade,
  person_id bigint not null references directory_people on delete cascade,
  primary key (group_id, person_id)
);
create index on directory_effective_memberships (person_id);

create table directory_effective_grants (
  person_id       bigint not null,
  target_group_id bigint not null,
  permission      text not null,
  primary key (person_id, target_group_id, permission)
);

-- the changefeed scim consumes
create table directory_membership_changes (
  id         bigint primary key generated always as identity,
  group_id   bigint not null,
  person_id  bigint not null,
  op         text not null check (op in ('added','removed')),
  caused_by  text,          -- "membership:123", "grant:7", "sweeper", "offboard:person:9"
  created_at timestamptz not null default now()
);

create table directory_scim_targets (
  app_id     bigint primary key references oauth_applications on delete cascade,
  base_url   text not null,
  token_ciphertext text not null,
  adapter    text not null default 'generic',   -- 'generic' | 'slack_grid' later
  last_reconciled_at timestamptz
);

create table directory_scim_links (
  app_id      bigint not null references oauth_applications on delete cascade,
  person_id   bigint references directory_people on delete cascade,
  group_id    bigint references directory_groups on delete cascade,
  external_id text not null,
  state       text not null,   -- 'active' | 'deactivated'
  check (num_nonnulls(person_id, group_id) = 1),
  unique nulls not distinct (app_id, person_id),
  unique nulls not distinct (app_id, group_id)
);
```

the rebuild (one service object, `Directory::Rebuild`, called inside every write transaction):

```sql
-- cycle check for a new group->group edge: is group_id reachable from member_group_id?
with recursive up as (
  select :group_id as g
  union
  select m.group_id from directory_memberships m join up on m.member_group_id = up.g
) select 1 from up where g = :member_group_id;   -- any row => reject

create temp table old_em on commit drop as table directory_effective_memberships;
truncate directory_group_closure, directory_effective_memberships, directory_effective_grants;

insert into directory_group_closure
with recursive c(ancestor_id, descendant_id, depth) as (
  select id, id, 0 from directory_groups
  union
  select c.ancestor_id, m.member_group_id, c.depth + 1
  from c join directory_memberships m on m.group_id = c.descendant_id
  where m.member_group_id is not null
) select ancestor_id, descendant_id, min(depth) from c group by 1, 2;

insert into directory_effective_memberships
select distinct c.ancestor_id, m.member_person_id
from directory_group_closure c
join directory_memberships m on m.group_id = c.descendant_id
where m.member_person_id is not null
  and (m.expires_at is null or m.expires_at > now());

insert into directory_effective_grants
select distinct em.person_id, c.descendant_id, g.permission
from directory_grants g
join directory_effective_memberships em on em.group_id = g.grantee_group_id
join directory_group_closure c on c.ancestor_id = g.target_group_id
join directory_groups t on t.id = c.descendant_id
where c.depth = 0 or (g.recursive and not t.protected);

insert into directory_membership_changes (group_id, person_id, op, caused_by)
select group_id, person_id, 'added',   :cause from (table directory_effective_memberships except table old_em) d
union all
select group_id, person_id, 'removed', :cause from (table old_em except table directory_effective_memberships) d;
```

queries everything else is built from:

- **claims for app X, user U**: `effective_memberships[U] ⋈ app_groups[X, approved]` → claim names.
- **may U log in to X**: no `app_requirements[X]` rows, or `∃` one with `(group, U) ∈ effective_memberships`.
- **may U do P to G**: `(U, G, P) ∈ effective_grants`.
- **does U see the group UI at all**: `∃ effective_grants[U]`.
- **what does app X know**: `app_groups[X]`. one query. the thing AD consumers could never answer.
- **where does group G leak to**: `app_groups[*, G]`.
- **offboarding review for U**: `memberships where member_person_id = U` with `created_by` and `created_at`. the implied ones vanish on their own.

## open decisions (yours)

1. **`kind` strictness.** recommended: the column plus constraints, with `app_groups` restricted to entitlements. looser option: one `kind`, a lint that warns when an exposed group gains a parent. stricter: two edge tables. i'd take the middle. it matches the words you already use.
2. **approval policy for exposure.** recommended: two-sided, with `trust_level` deciding who may approve. alternative: group manager alone (faster, phishable) or directory admin alone (safe, bottleneck).
3. **do directory admins bypass `app_requirements`?** recommended: no. entra's silent global-admin bypass is a known footgun.
4. **depth cap.** 4? it's a UI readability constraint more than a performance one.
5. **LDAP now or later.** the model supports it as a projection; nothing in the core depends on it. later, unless something needs it this quarter.
6. **what happens to a scim-linked person who is deactivated on `identities` but still in an entitlement.** okta leaves them in pushed groups. recommended: `directory_people` deletion cascades, and identity deactivation deletes the directory row.
7. **saml SP config into the database.** required for `app_groups` to reference SAML apps. it's also the thing that lets `allowed_emails` die. separate PR, probably first.

## appendix: why not an external engine or directory server

| | **A. postgres tables (recommended)** | B. embed spicedb / openfga | C. stand up kanidm, federate to it |
|---|---|---|---|
| what it is | `directory_*` tables in this db; closure rebuilt per write; oidc/saml/ldap/scim read one materialized table | zanzibar-style tuple store as a sidecar service; rails writes tuples, calls Check/Lookup | a real directory server owns people+groups; HCA becomes an OIDC client of it for staff |
| fits the scale | 150 people, 50 groups, ~20 writes/day: full rebuild is sub-millisecond | overkill. built for millions of objects and many services checking | fits, but it's a second system with its own admin UI, backup, upgrade cadence |
| diffs for SCIM | free (snapshot, rebuild, `EXCEPT`) | not in OSS. authzed Materialize is dedicated-tier only. openfga `ReadChanges` is tuple-level, no expansion | kanidm has SCIM API; outbound reconciler still ours to write |
| "app X may know group G" | one table, we're the only caller | always a layer above the engine; FGAM is enterprise-only | kanidm's claim maps are per-client, configured by oauth2 admins (app-side) |
| dual-write | none | yes: memberships table for the admin UI + tuples, no shared transaction, needs outbox+reconciler | yes: HCA identities + kanidm persons, linked by hand |
| LDAP view | we write a read-only projection (kanidm/lldap shape; ~flat `ou=people`/`ou=groups`) | n/a | native |
| cost | a few tables, one rebuild service, protocol adapters we were writing anyway | a go service, a second postgres db, grpc, preshared keys, migrations, plus everything in A except the closure | ops of a second identity system; split brain on who's staff |

A. the research is unusually unanimous here: oso's own ReBAC guide says "we don't recommend using the centralized relationship model in general"; the zanzibar paper's leopard index *is* option A; the engines treat nested groups as the hard path and keep shipping correctness fixes for it. door B is the right answer for a different problem. door C is the right answer if we wanted to stop owning the directory, which we don't.

## research files

- `research/01-workforce-idps.md` — okta, entra, google workspace, jumpcloud, onelogin, rippling, aws identity center
- `research/02-active-directory.md` — the AD model in depth: linked attributes, primaryGroupID, scope, AGDLP, AdminSDHolder, token bloat, what to keep
- `research/03-self-hosted-directories.md` — AD (second pass), openldap, freeipa, kanidm, keycloak, authentik, zitadel, lldap, authelia; the LDAP-projection question
- `research/04-relationship-engines.md` — zanzibar paper, spicedb, openfga, keto, cedar/opa/oso, postgres closure patterns, exclusion, diffs; includes the schema sketch this doc's schema is based on
- `research/05-app-platforms-and-populations.md` — github, slack grid, atlassian, discord, google groups, k8s, aws iam, posix, modern saas; the workforce/customer split across entra, okta/auth0, keycloak, cognito, google; third-party oauth app risk
