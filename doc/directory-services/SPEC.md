# directory services

> spec, 2026-10-21. supersedes the thinking-out-loud in `README.md` wherever they disagree. background research is in `research/`.

## 1. what this is

a small directory inside hca for the people we actually manage: staff, contractors, gap years, special little dudes. roughly 150 people out of 50,000 identities. it answers four questions and nothing else:

1. who is in what group.
2. who is allowed to change that.
3. which apps are told about which access, and what they call it.
4. whose sessions to cut on which apps when (1) changes.

it is the source of truth for group membership. every protocol (oidc, saml, later ldap) is a read over one flattened table.

### goals

- one encoding of membership, flattened on every write, read by everything.
- delegation that's a table you can `SELECT` from, not a permission model you need a graph database to audit.
- apps learn nothing unless someone with the right to say so says so, and they learn it under a name we choose.
- community identities are structurally outside. not filtered out. outside.
- every "but what about…" is a row, not a feature.

### non-goals (for now)

- dynamic / rule-based groups.
- negative membership ("everyone except").
- organizational units or any second hierarchy.
- ldap. the model supports a read-only projection; it is not in scope.
- **scim, in either direction.** no provisioning into other systems from the directory. it's a second product with its own failure modes and it is not in v1. if it ever happens it's a separate spec that reads the same outbox.
- replacing `backend_users` roles. the admin console keeps its booleans.
- slack grid account provisioning. `SCIMService` provisions every identity who logs in to slack, keyed off onboarding scenario. that's account-level, for all 50,000, and unrelated to the directory. it stays exactly as it is. the directory never pushes anything to slack; slack is one workspace and channels are channels.

## 2. vocabulary

| word | meaning | who says it |
|---|---|---|
| **collection** | the umbrella for group and entitlement. schema only; never appears in UI copy. | the database |
| **group** | a collection of people. "gap year." "fulltimers." gap years *are* fulltimers. | everyone |
| **entitlement** | a collection that means access. "docs access." "control plane." fulltimers *get* docs access. | everyone |
| **member of** | the only relationship. "x is a member of y" means everyone in x is automatically in y. | everyone |
| **effective member** | in it directly, or through any chain of member-of. | UI says "via …" |
| **grant** | "members of group a may do p to collection b." | admin UI |
| **expose** | the permission to tell an app about an entitlement. | admin UI, app page |
| **directory person** | an identity that has been brought into the directory. | schema, admin UI |
| **directory services admin** | a `backend_user` with the `directory_services_admin` flag. root for the directory. lives outside the graph. | admin UI |

verbs in UI copy: groups **are**. entitlements **get**. "gap year are fulltimers." "fulltimers get docs access."

every collection and every app has a `slug` that never changes after creation. names change; slugs don't. yaml, claims config, and urls reference slugs.

## 3. the model

### 3.1 people

`directory_people` has one row per identity that is in the directory. that row is the boundary. nothing in the directory can reference an identity without it: memberships, grants, and effective tables all FK to `directory_people`, not `identities`.

a row comes into existence three ways:

1. **an admin brings someone in** from the admin people page, which is the only place that searches all 50,000 identities.
2. **a backend user is given the `directory_services_admin` flag.**
3. **a manager grants them something.** anyone holding `manage_members` on a collection can add a person *by exact email*. if that email belongs to an identity that isn't yet a directory person, the row is created and the membership added in one step. this is how gap years bring on contractors without an admin: the admin once makes a `ysws-contractors` group that feeds the right entitlements and grants gap year `manage_members` on it; from then on gap year types an email and the contractor has everything, and removes them and it all goes away.

the definition this implies, and the one to hold on to: **a directory person is someone who was given something by someone with the right to give it.** no org-email restriction, no approval; the right to add to a collection is the right to bring someone in through it.

if the email has no hca account yet, the add fails with "no hca account with that email." the person signs up, the manager adds them. no invitation system; it was considered and cut as not worth a table.

add-by-email is an oracle for "does this email have an hca account." we accept that and audit it: every attempt is logged with who typed what, including misses; it's rate limited per person; and the failure message is honest ("no hca account with that email") because the twenty people who hold `manage_members` need to know when they've typo'd. a manager probing forty emails in a minute is a report, not a design flaw.

**offboarding is locking the identity.** that's the thing that already happens when someone leaves, so the directory keys off it rather than inventing a second step. a locked (or banned, or deleted) identity can't log in, so its effective memberships are inert, and the revokers (§9) fire on lock to end whatever sessions are open. memberships are *kept*: unlocking restores exactly what the person had, which is what you want for a contractor who comes back. locked people show a badge everywhere they appear and are listed on a "locked, still in directory" report so an admin can purge them when it's clearly permanent.

a row is deleted by an admin ("remove from directory") when it is permanent. deletion cascades through memberships, which triggers a rebuild, which emits removals, which revokes tokens and sessions on every app that cares (§9). one delete. a directory person who holds nothing (no memberships, no grants, no admin flag) is listed on the "holds nothing" report for an admin to remove or leave; never auto-deleted.

community identities never have a row. they are not filtered out of anything; there is nothing to point at.

### 3.2 collections

one table, `directory_collections`, with `kind ∈ {group, entitlement}`. rails sees `Directory::Collection` with STI subclasses `Directory::Group` and `Directory::Entitlement`.

| | group | entitlement |
|---|---|---|
| may contain people (direct) | yes | yes |
| may contain groups | yes | yes |
| may contain entitlements | no | no |
| may be a member of | groups, entitlements | nothing |
| may be exposed to apps | no | yes |
| may be required to log in | no | yes |
| created by | admin | admin |

so the nesting matrix is: person → group; person → entitlement; group → group; group → entitlement. everything else is a constraint violation.

an entitlement has two kinds of direct member and they're governed differently. its member **groups** are structure ("which groups get this"): admin-only. its direct **people** are one-offs ("this kid also gets docs access"): delegated via `manage_members`. "gap year manages docs access" means gap year can add and remove individual people on `docs-access` and cannot touch which groups feed it. (an earlier draft put the one-off people in a separate "native group" per entitlement; a group that can't be nested or granted on is just a person-in-an-entitlement with extra steps, so it's gone.)

why entitlements are terminal: so that holding manage-members on an entitlement can only ever grant that one entitlement. if entitlements could be members of groups, adding someone to `docs-access` could make them a fulltimer and therefore a member of everything fulltimers get. a one-entitlement delegation would become "mint fulltimers." with entitlements terminal, the blast radius of any delegated add is exactly one entitlement, forever.

what the kinds do **not** prevent: an admin nesting "all staff" into "prod deployers." that's the allowed direction. it's an admin action (member groups of an entitlement are structure), and the guardrail is a confirmation that says "this adds 150 people."

`protected` is a boolean on collections. a protected collection cannot be reached by a recursive grant; only grants naming it directly apply. this is AdminSDHolder as a column instead of an hourly cron. admin-only to set.

### 3.3 memberships

`directory_memberships(collection_id, member_person_id | member_group_id, created_by_identity_id, expires_at, created_at)`. exactly one of the member columns is set. the row belongs to `collection_id`; authorization is always checked against `collection_id`, never against the member. (kanidm's note: "there is a security benefit to 'groups have members' rather than 'users are members of groups'. that benefit is delegated administration.")

invariants, enforced at write:

- no cycles. a recursive CTE from the new parent upward must not reach the new child.
- depth ≤ 6, measured as the longest person-to-root path through the new edge. a readability constraint so the UI can always show the path, not a security one.
- kind matrix from §3.2.
- `expires_at`, if set, is in the future at write time. a sweeper job (every few minutes) deletes expired memberships through the normal write path, so the removal rebuilds, diffs, and audits exactly like a manual one. the rebuild itself never reads the clock; an expired-but-not-yet-swept membership is still effective until the sweeper runs.

### 3.4 effective membership

`directory_effective_memberships(collection_id, person_id)` is the flattened answer: every (person, collection) pair reachable through member-of. it is rebuilt on every write to memberships or grants (§6). it is the **only** table any consumer reads. tokens, saml, the app page, the group page's "also includes", revocation, the admin UI's gate. nobody walks the edges at read time except the rebuild and the "via" path display.

### 3.5 grants

`directory_grants(grantee_group_id, target_collection_id, permission, recursive, created_by_identity_id, created_at)`.

permissions, v1:

| permission | lets you | recursive allowed |
|---|---|---|
| `view` | see the collection and its members in `/directory` | yes |
| `manage_members` | on a group: add and remove direct members (people and groups). on an entitlement: add and remove direct *people* only; member groups are admin-only | groups only |
| `expose` | write exposure rows pointing at the target entitlement (§7.1) | yes |

`recursive=true` means the grant also applies to every collection reachable *downward* from the target via member-of (its sub-groups), stopping at `protected` ones. it never applies upward: holding manage-members on fulltimers says nothing about docs access, because docs access isn't inside fulltimers, fulltimers is inside it. the walks go opposite directions and can't cross.

**recursive grants may not target entitlements.** an entitlement's members are groups you don't necessarily own; "manage-members, recursive, on docs-access" would reach fulltimers because fulltimers is a member of docs-access. that's the escalation the kinds exist to prevent, arriving through the grants table. a grant on an entitlement applies to the entitlement's direct people and nothing further. enforced as a model validation.

grants are written and deleted by directory services admins only. there is no delegated "manage grants" in v1. (it exists as a word in the research; it's the escalation primitive and we don't need it at 150 people.)

grantees are groups, never people. "nora can manage x" is "nora is in a group that can manage x." this keeps the grants table small and keeps delegation visible as a group.

grants can point anywhere, including at a group the grantee is a member of, or at itself. "fulltimers manage fulltimers" is valid and normal. grants do not participate in the cycle check; only memberships do.

`directory_effective_grants(person_id, target_collection_id, permission)` is derived alongside effective memberships: expand grantee groups through effective membership, expand targets through the closure (respecting `recursive` and `protected`). "can person p do q to collection c" is a primary-key lookup.

### 3.6 admins

`backend_users.directory_services_admin` (boolean). root for the directory: every permission on every collection, create and delete collections, write grants, set `protected`, bring people in and remove them, run the drift check.

it lives outside the graph on purpose. no grant, no membership, no rebuild can produce it. the grants table can express "this group, that collection" and nothing broader, so reading it never needs a footnote. this is what Domain Admins would be if it couldn't have members and couldn't be nested into.

setting the flag creates the backend user's `directory_people` row if missing. clearing the flag does not remove the row.

anyone who can edit backend users (super admins) can set this flag on themselves. that's one audited click, not a boundary. the flag separates the directory's root from the grants table; it does not separate it from the people who already run the admin console.

### 3.7 exposures and requirements

`directory_exposures(app_id, entitlement_id, claim_name, created_by_identity_id, created_at)`: "app a is told about entitlement e, and a calls it `claim_name`." unique on `(app, entitlement)` and on `(app, claim_name)`.

`directory_app_requirements(app_id, entitlement_id)`: "to log in to a at all you must be an effective member of e." multiple rows = any-of.

both are kept as separate tables because they live on different lifecycles. "must be in to log in" is a security decision; "is told about" is an app-integration decision. revoking access shouldn't mean touching claim config.

there is no approval workflow. writing an exposure row requires all three of:

1. the writer is an owner of the app (`program_collaborators` accepted, or an organizer), **and**
2. the writer holds `expose` on the entitlement (effective grants), **and**
3. the app's `trust_level` is `hq_official`.

(3) exists because a staff member can own a community-trust-level side project. without it they could wire `internal-apps` to it and the app would receive `staff` claims. all three checks live in one policy method. requirements use the same check. unwiring (deleting an exposure or requirement) is allowed to the app's owner, to anyone holding `expose` on the entitlement, or to an admin, so an entitlement's manager can always revoke an app's knowledge of it.

saml SPs are wired in yaml (§7.2) and have no trust level; the pull request review is the check.

one side effect of wiring, because it changes no membership and so produces no diff: writing a **requirement** revokes doorkeeper tokens (and calls the app's revoker, §9) for every current token holder on that app who is not an effective member of the entitlement.

exposures and requirements are what the directory UI calls "wiring." the self-serve case: an admin creates entitlement `internal-apps` with fulltimers as a member and grants fulltimers `expose` on it. any fulltimer standing up an internal app wires it from their app page without talking to anyone. a community app owner sees the same section with the copy "this app isn't told about any groups. only staff can wire that."

this closes [#312](https://github.com/hackclub/auth/issues/312).

## 4. who can do what

| action | requires |
|---|---|
| see `/directory` nav at all | admin, or any effective grant |
| see "my access" | any directory person |
| see a collection page | admin, or `view` / `manage_members` / `expose` on it |
| add / remove a direct person of c | admin, or `manage_members` on c |
| add / remove a member *group* of a group g | admin, or `manage_members` on g |
| add / remove a member *group* of an entitlement | admin |
| create / delete / rename a collection | admin |
| set `protected` | admin |
| write / delete a grant | admin |
| bring an identity into the directory / remove them | admin |
| wire an exposure or requirement on app a for entitlement e | own a + `expose` on e + a is `hq_official` |
| unwire | own a, or admin |
| csv import | admin |
| run the drift check; configure an app's revoker | admin |

delegated verbs are exactly: add member, remove member, wire. everything structural is an admin. at 50 people that's a few actions a month and that's the point.

## 5. data

all tables prefixed `directory_`. ids are bigints; slugs are the human handle and are immutable.

```sql
create table directory_people (
  id            bigint primary key generated always as identity,
  identity_id   bigint not null unique references identities,
  created_by_identity_id bigint references identities on delete set null,
  created_at    timestamptz not null default now()
);

create table directory_collections (
  id            bigint primary key generated always as identity,
  slug          text not null unique,
  name          text not null,
  kind          text not null check (kind in ('group','entitlement')),
  protected     boolean not null default false,
  description   text,
  created_by_identity_id bigint references identities on delete set null,
  created_at    timestamptz not null default now()
);

create table directory_memberships (
  id               bigint primary key generated always as identity,
  collection_id    bigint not null references directory_collections on delete cascade,
  member_person_id bigint references directory_people on delete cascade,
  member_group_id  bigint references directory_collections on delete cascade,
  created_by_identity_id bigint references identities on delete set null,
  expires_at       timestamptz,
  created_at       timestamptz not null default now(),
  check (num_nonnulls(member_person_id, member_group_id) = 1),
  check (member_group_id is distinct from collection_id),
  unique nulls not distinct (collection_id, member_person_id),
  unique nulls not distinct (collection_id, member_group_id)
);
-- model validations: kind matrix (§3.2), no cycle, depth <= 6, member_group.kind = 'group'

create table directory_grants (
  id                   bigint primary key generated always as identity,
  grantee_group_id     bigint not null references directory_collections on delete cascade,
  target_collection_id bigint not null references directory_collections on delete cascade,
  permission           text not null check (permission in ('view','manage_members','expose')),
  recursive            boolean not null default false,
  created_by_identity_id bigint references identities on delete set null,
  created_at           timestamptz not null default now(),
  unique (grantee_group_id, target_collection_id, permission)
);
-- model validations: grantee.kind = 'group'; recursive => target.kind = 'group'

create table directory_exposures (
  id             bigint primary key generated always as identity,
  app_id         bigint not null references oauth_applications on delete cascade,
  entitlement_id bigint not null references directory_collections on delete cascade,
  claim_name     text not null,
  created_by_identity_id bigint references identities on delete set null,
  created_at     timestamptz not null default now(),
  unique (app_id, entitlement_id),
  unique (app_id, claim_name)
);
-- model validation: entitlement.kind = 'entitlement'

create table directory_app_requirements (
  app_id         bigint not null references oauth_applications on delete cascade,
  entitlement_id bigint not null references directory_collections on delete cascade,
  primary key (app_id, entitlement_id)
);

-- derived. never written by anything but Directory::Rebuild.
create table directory_closure (
  ancestor_id   bigint not null references directory_collections on delete cascade,
  descendant_id bigint not null references directory_collections on delete cascade,
  depth         int not null,
  primary key (ancestor_id, descendant_id)
);

create table directory_effective_memberships (
  collection_id bigint not null references directory_collections on delete cascade,
  person_id     bigint not null references directory_people on delete cascade,
  primary key (collection_id, person_id)
);
create index on directory_effective_memberships (person_id);

create table directory_effective_grants (
  person_id            bigint not null references directory_people on delete cascade,
  target_collection_id bigint not null references directory_collections on delete cascade,
  permission           text not null,
  primary key (person_id, target_collection_id, permission)
);

-- outbox
create table directory_membership_changes (
  id            bigint primary key generated always as identity,
  collection_id bigint not null,
  person_id     bigint not null,
  op            text not null check (op in ('added','removed')),
  cause         text not null,     -- "membership:123" | "grant:7" | "sweeper" | "person_removed:9" | "import:…"
  created_at    timestamptz not null default now()
);
create index on directory_membership_changes (created_at);
```

the revoker table is in §9.

`created_by_identity_id` is an identity everywhere because backend users have identities and admins will author most early rows. it is `on delete set null` everywhere because this app deletes identities (see `doc/DELETIONS.md`) and a directory row must never block that.

rails models: `Directory::Person`, `Directory::Collection` (+ `Group`, `Entitlement` via STI on `kind`), `Directory::Membership`, `Directory::Grant`, `Directory::Exposure`, `Directory::AppRequirement`, `Directory::EffectiveMembership`, `Directory::EffectiveGrant`, `Directory::MembershipChange`. memberships and grants get `has_paper_trail`. changes to memberships, grants, exposures and requirements emit `public_activity` on both the collection and the person.

## 6. the rebuild

`Directory::Rebuild.call(cause:)` runs inside the same transaction as every write to memberships, grants, people (delete), or collections (delete), **once per transaction**, after all writes and before commit. a csv import of 300 rows is one rebuild, not 300. it is a plain service object, not a trigger.

0. **lock**: `pg_advisory_xact_lock` on a fixed key. two overlapping rebuilds would each diff-apply from their own snapshot and leave the derived tables as neither; serializing writers costs nothing at our volume and readers are unaffected.
1. **snapshot** `directory_effective_memberships` into a temp table.
2. **compute** closure, effective memberships, effective grants into temp tables with one recursive CTE each.
3. **apply the diff**: `DELETE` rows in the real tables that aren't in the temp ones; `INSERT` rows in the temp ones that aren't in the real ones. row locks only. **do not `TRUNCATE`**: it takes an exclusive lock and a login reading effective memberships would wait on the rebuild. readers must never block on a write.
4. **emit**: `(new − old)` as `added`, `(old − new)` as `removed`, into `directory_membership_changes` with `cause`.
5. after commit: enqueue `Directory::AfterChangeJob` for the new change ids. **nothing inside the rebuild or the write path may enqueue, notify, or call out before commit.** what-if previews (§8.7) run this same path and roll back; a `deliver_later` inside the service would make a preview of "remove nora" log nora out of everything.

`Directory::AfterChangeJob` does two things per change row:

- **token revocation.** for `removed` on an entitlement, revoke doorkeeper access and refresh tokens for that person on every app that has a requirement or an exposure on that entitlement. this is the cheap, immediate half of "sign out everywhere." the rest is [#348](https://github.com/hackclub/auth/issues/348).
- **revokers.** for the same `removed` rows, call the session revoker of every affected app that has one (§9).

cost: at 150 people, 50 collections, 20 writes a day, the full compute is well under a millisecond. incremental closure maintenance (path counts, triggers) is where the bugs live and buys nothing here. if the directory ever grows past full-rebuild, the upgrade is a path-counting closure table and nothing above the derived tables changes.

`Directory::Validate` (nightly, and a button): recompute into temp tables and compare against the real derived tables. report any difference loudly. this is dcdiag.

## 7. protocol integration

### 7.1 oidc

- the id token and userinfo include `groups: [claim_name, …]` = `claim_name` for every exposure of the app whose entitlement the user is an effective member of, **whenever the app has at least one exposure**, under the `openid` scope. it is not gated on a `groups` scope: exposure already means "this app may know," and many consumers (kubernetes, argo, grafana, vault, gitlab) have fixed scope lists you can't edit, so a required scope would silently give them nothing. a `groups` scope exists so apps that want to request it explicitly can, but it is not required. no exposures: no claim at all. it goes in **both** id token and userinfo, always, because consumers split on which one they read.
- standards: `groups` is an IANA-registered JWT claim (RFC 9068 §2.2.3.1, semantics from SCIM RFC 7643 §4.1.2). 9068 says to encode per 7643, whose `groups` is technically an array of objects; every IdP in practice emits an array of strings and every consumer expects strings. we emit strings. the `groups` *scope* has no standard; it's the common convention. our doorkeeper access tokens are opaque, so the claim lives in the id token and userinfo, which is where RPs read it. if we ever adopt JWT access tokens, 9068 is the profile to follow and `groups` goes there too.
- `directory_app_requirements` is enforced in **two** places. first, in the authorization flow before consent: not a member of any required entitlement → an error page naming the app ("this app is for hack club staff") and nothing else. second, when a **refresh token is redeemed**: an app holding a refresh token can mint access tokens for weeks without the user touching the authorize page, so a requirement added after the token was issued would never be seen. the requirement-write trigger (§3.7) revokes those tokens, but if that job is delayed there's a window; the check at refresh closes it. same policy method, called from doorkeeper's authorize flow and from its token-endpoint hook for the `refresh_token` grant. directory admins do **not** bypass either. both are logged.
- the claim comes from `effective_memberships ⋈ exposures`; nothing in the oidc path ever reads `memberships`. doorkeeper-openid_connect (1.8.x) calls each claim block with `(resource_owner, scopes, access_token)`, and `access_token.application` is the app, so the per-app claim is an ordinary `normal_claim` block. verified against the gem source, no patch needed.

### 7.2 saml

saml service providers stay in `config/saml.yml` and are reviewed through pull requests. the yaml gains two keys per SP, by entitlement slug:

```yaml
- slug: airtable
  required_entitlements: [airtable-users]
  entitlements:
    airtable-users: "airtable"          # claim/attribute value the SP sees
    fulltimers-apps: "staff"
```

the saml controller treats `required_entitlements` as `directory_app_requirements` and `entitlements` as exposures, read from yaml rather than the table. the attribute carrying the values is named by an optional `groups_attribute:` key per SP (default `groups`), because saml has no standard attribute name for this. `allowed_emails:` is deprecated and removed once each SP that uses it has an entitlement. the entitlement page's "apps told about this" lists yaml SPs alongside oidc apps so the view is complete.

a slug named in yaml that no longer exists **fails closed**: a `required_entitlements` entry that doesn't resolve means nobody can log in to that SP, with a sentry alert and an error page that says why. the delete confirmation for an entitlement lists every yaml SP that references its slug.

`allowed_attributes:` is unrelated (per-attribute filtering of profile fields) and stays.

### 7.3 sign-out

losing membership does not end an app session; that's the protocols, not us. we do what the protocols allow: revoke our own tokens immediately (§6), keep token lifetimes short, and write the gap down. unified sign-out across saml and oidc (SAML SLO, OIDC back-channel logout, Shared Signals/CAEP `session-revoked` and `token-claims-change`) is specified in [#348](https://github.com/hackclub/auth/issues/348) and is out of scope for the directory itself. the directory's job is to emit the diff; #348's job is to tell apps about it.

## 8. UI

### 8.1 where it lives

`/directory`, a new area. the nav link appears if you are a directory services admin or hold at least one effective grant. no grants: no link, no 403, nothing. members of `docs-access-users` never learn the page exists.

"my access" at `/directory/me` is visible to any directory person, grants or not. it's the page most people will ever see.

a search box at the top of `/directory` finds people and collections. people results follow the picker's rules (§8.2): directory people only, name and login email, three characters minimum. without it, finding a person means finding a group they're in first.

**empty states.** an admin on day one sees zero collections and a sentence saying what to do first. a manager whose grants reach exactly one collection lands on that collection, not on a list of one.

the app page under `/developer_apps` gets a "directory" section (§8.5). it is the only place app owners touch the directory.

### 8.2 the picker

one shared widget, used by every "add" button. type part of a name; it resolves people and collections, filtered to what the current action allows (people only; groups only; entitlements you hold `expose` on). multi-select. paste a list of emails and it resolves them in bulk and underlines the ones it couldn't. this is the "Select Users or Groups" dialog. build it once, well.

scoping rules, because this is the one surface where a manager could learn something they shouldn't:

- it searches **`directory_people` only** for name matches. never identities. the 50,000 are unreachable from it. the single exception is the admin people page, which is admin-only.
- an **exact email** that matches an identity outside the directory is the add-by-email door (§3.1): it resolves to "will be brought into the directory." an exact email matching nothing says so.
- it shows **name and login email**, nothing else. no legal name, phone, address, verification state, slack id. those live on the identity and the directory never surfaces them.
- minimum three characters, small page size, no "list everyone."


### 8.3 collections

**list.** flat. search. each row: name, kind badge, member count, "you can: view / manage members / expose."  admins see everything; everyone else sees what their grants reach.

**collection page.**

- the header shows both numbers: **"12 direct · 47 total."** the gap is the whole point of the fold.
- **members** (direct). the editable list. add (picker), remove. for an entitlement this is two tabs: **groups** (admin-editable) and **people** (editable with `manage_members`). sortable by name, added date, added by, expiry; "who added all these" is the first audit question. rows with `expires_at` show "expires in 3 days" and an extend button.
- if the viewer can see the page but not edit it, the add and remove controls are present and disabled, and the disabled state says **who can**: "needs manage members on this group · held by fulltimers-admins." the managed-by section already shows this; it's repeated where the frustration happens.
- **also includes** (effective minus direct), folded by default. each row shows every path: "nora · via gap year → fulltimers." all paths, not one; if there are two, removing one doesn't remove access and the page should make that obvious before someone finds out. path segments render only through collections the viewer can see; otherwise the segment reads "via 2 groups you can't view." holding view on docs-access must not teach you who is in gap year.
- **managed by.** the grants targeting this collection, with `recursive` and the path if inherited from a parent's recursive grant. admins can add and remove here.
- **entitlements only: apps told about this.** app, claim name, who wired it, when. yaml SPs listed read-only with a "config/saml.yml" badge.
- **entitlements only: required by.** apps that require this to log in.
- **activity.** every change to this collection, who and when.
- **export.** download this collection's direct and effective members as csv.

every via-path segment, every group name, every person name is a link if the viewer can see the target. group ↔ person ↔ app navigation is the whole UI and it must never dead-end.

removal confirmation shows the consequence: "nora will still get docs access via gap year → fulltimers" or "nora will lose docs access and be signed out of cloudflare access."  if the removal would cost the current user a grant they're relying on ("fulltimers manage fulltimers" and you're removing the group you're in), the confirmation says "you will lose the ability to manage this."


### 8.4 people

**person page** (admin or anyone with view on something they're in). effective memberships grouped by direct / via, each via with its full path, **filtered to collections the viewer can see**; a manager with view on one group does not get anyone's whole membership list. what they can manage. a locked / banned badge when the identity is. activity. "remove from directory" with a confirmation listing what they lose in numbers.

**my access** is the person page for yourself, read-only, with the "via" paths and the list of apps that are told about something you're in. "why can i get into that app" answered without a ticket.

### 8.5 the app page section

on an oidc app's page:

> **directory**
> told about: `internal-apps` as **staff** (wired by nora, oct 21) · remove
> required to log in: `internal-apps` · remove
> [add…] — picker shows entitlements you hold expose on
> [preview as…] — pick a person: shows the exact `groups` claim this app would receive and whether they'd pass the requirement

for a community-trust-level app, the same section reads: "this app isn't told about any groups. only hack club staff can wire that." no add button.

**the consent screen.** doorkeeper's authorize page already lists scopes by trust level. when the app has exposures the user is a member of, it also says: "this app will be told you're in: staff." the one moment a person sees what's about to be disclosed about them. if an hq app is configured to skip consent, "my access" is where they see it instead.

**the "you can't log in" page.** two of them, one in the oidc authorize flow and one in the saml controller, same copy. it names the app and says who it's for ("this app is for hack club staff") and nothing else: not the owner, not the entitlement slug, not which requirement failed. a community kid who follows a link to an hq app learns only that it isn't for them.

### 8.6 admin pages

- **people**: bring an identity in (picker over identities), remove.
- **new collection**: name, slug (auto, editable until save, immutable after), kind, description.
- **grants**: lives on the collection page; there is also a flat "all grants" table with search, because the whole point is that it's a table.
- **reports**: empty collections; collections with no manage-members grant; directory people who hold nothing; locked identities still in the directory; direct memberships older than a year; direct memberships with `expires_at` in the next 30 days; entitlements exposed to more than n apps; add-by-email misses per person in the last day.
- **health**: last validate result **with the mismatched rows shown**, not just "drift: yes"; last revoker call per app and its outcome; "run now."
- **activity**: a global feed across the directory, newest first. "what happened today."
- **view as**: pick a directory person and see `/directory` exactly as they see it. the fastest answer to "why can't i see x," and RSoP for the UI itself.
- **export**: the whole directory (people, direct memberships, grants, exposures, requirements) as csv. the import's mirror.
- **import**: csv of `email, collection slug, expires_at?`. dry-run shows the diff first.

### 8.7 what-if

v1: only in destructive confirmations (remove member, delete collection, remove person), as a preview computed by running the rebuild in a transaction and rolling back. the text is "n people lose x; m keep it via y." the preview's transaction opens and rolls back **inside one request**; the result is a plain diff handed to the view. it must never hold the rebuild's advisory lock across the round trip while a human reads the dialog.

later: a standalone planning page. pick a change, see the full diff and every downstream effect, apply or discard. it's the same code; the confirmation dialogs are the mvp of it.

### 8.8 notifications

slack dm via the identity's existing `slack_dm_channel_id`, phase 2:

- added to an **entitlement** (directly or via a group): "you now have docs access." not on group adds; too noisy and groups aren't access.
- removed from an entitlement, same shape.
- three days before a membership's `expires_at`, to the person and to whoever added them.

nothing else. no digests, no "someone viewed your page."

### 8.9 the boring list

- i18n from the first view. the repo already has open issues for missing keys; a new area must not hardcode english.
- the picker and the fold work on a phone.
- badges (kind, protected, locked) carry text, not just color.
- the activity feed paginates; nothing else needs to at this size.

## 9. revokers

losing membership kills our own tokens immediately (§6) but not the session an app already holds. for apps that offer a "log this user out" api, a **revoker** closes that gap. it's the only outbound integration in v1 and it's deliberately tiny: no users pushed, no groups pushed, no state kept on the other side. one call, one email, when something is taken away.

### 9.1 when it fires

for an app with a revoker configured, call it for a person when any of:

- a `removed` row lands in the outbox for an entitlement the app is told about or requires (via `Directory::AfterChangeJob`);
- a requirement is added to the app and the person holds a token but isn't an effective member;
- the person is removed from the directory;
- the person's identity is locked, banned, or deleted. (tokens are already dead for locked identities; the revoker is for the app's own session.)

it never fires on `added`. adding is the next login's job.

### 9.2 shape

```
Directory::Revokers::Base      #call(email:) -> :ok | :failed(reason)
Directory::Revokers::CloudflareAccess
```

cloudflare access is the first and, for v1, only adapter: `POST /accounts/{account_id}/access/organizations/revoke_user` with `{ email }`, authenticated with an api token holding only `Access: Organizations Revoke`. response is a boolean. cloudflare's own caveat: a revoked user can log back in if the IdP still says yes; by the time we call this the claim is already gone, so they can't.

calls are good_job jobs after commit, retried with backoff, never blocking. outcome and timestamp are recorded per (app, person) and shown on the health page and the person page. a failing revoker is loud and never fatal.

### 9.3 table

```sql
create table directory_app_revokers (
  app_id            bigint primary key references oauth_applications on delete cascade,
  adapter           text not null,                 -- 'cloudflare_access'
  config_ciphertext text not null,                 -- account id, api token
  enabled           boolean not null default true,
  last_called_at    timestamptz,
  last_result       text
);
```

admin-only to configure. it's a credential that can log people out of things.

## 10. operations

- **bootstrap**: set `directory_services_admin` on one backend user in console. that creates their directory row. everything else is UI.
- **migration**: csv import of current staff into groups. entitlements created by hand. `allowed_emails` SPs get an entitlement each and the yaml key; then `allowed_emails` is removed.
- **audit**: public_activity on every change, on both the collection and the person. paper_trail on memberships and grants, with "restore" exposed in the UI for the last n days. this is the recycle bin. restore goes through the normal write path (build a new membership from the version's attributes and save it), never `reify.save`, which would skip validations and the rebuild.
- **drift**: `Directory::Validate` nightly; result on the health page; sentry on mismatch.
- **orphans**: a collection with no `manage_members` grant is only editable by admins. the report lists them. with recursive grants on top-level groups this is rare; it's accepted that admins rescue the rest.
- **deleting a collection** cascades memberships, grants, exposures, requirements. the confirmation says what that does in numbers. `protected` collections require typing the slug.
- **identity deletion** (the `deletions` flow) must call "remove from directory" explicitly *before* deleting the identity. the FK cascade would delete the rows, but the rebuild is a service object, not a trigger, so a bare cascade emits no diff and no revoker fires. one line in the deletion job; the spec exists so it doesn't get forgotten.
- **the last admin** cannot clear their own `directory_services_admin` flag. refuse with a message.
- **retention**: `directory_membership_changes` is also the history of "why did nora get docs access in october." it is never pruned. at our volume it doesn't need to be.
- **staging** has no directory data; seeds create one admin, two groups, one entitlement, one exposure.

## 11. phases

**phase 1 — the directory.** the rebuild and its test suite *first*, before any UI: ten-row fixtures covering diamond paths, multiple parents, depth, cycle rejection, protected stops, and grant expansion, because a wrong closure doesn't throw, it quietly puts people in or out of things. then people, collections, memberships, grants, effective tables, outbox, `/directory` list and collection pages, person page, my access, picker with add-by-email, admin flag, csv import, activity, the "holds nothing" report. no apps yet. useful on its own as "who's on what team" with delegated editing.

**phase 2 — apps.** exposures, requirements, the app page section, preview-as, `groups` scope and claim, requirement enforcement in oidc authorize, saml.yml keys and controller support, `allowed_emails` migration, doorkeeper revocation on `removed`, removal confirmations with "still has via …". closes #312.

**phase 3 — revokers.** the revoker table, the cloudflare access adapter, the four triggers, outcomes on the health and person pages, consequence text in confirmations. small enough that it may fold into phase 2.

**later, separately, if ever:** scim provisioning as its own spec reading the same outbox. sign-out everywhere (#348). standalone what-if page. ldap projection. expiry UI beyond the optional date on add. dynamic groups as rules that *write* memberships.

## 12. open questions

1. `expires_at` on memberships: the column and sweeper are in phase 1; is the optional "until" date in the add dialog phase 1 too, or does it wait? (cheap; i'd include it.) sweeper cadence: every 5 minutes is fine.
2. (removed: native groups are gone; people go directly in entitlements.)
3. does `view` deserve to exist in v1, or is "you can see what you can manage" enough until someone asks?
4. preview-as: should it be available to app owners (useful for debugging) or admins only (it reveals a person's memberships to whoever owns the app)? i'd say app owners, limited to people who are effective members of something the app is told about.
5. cloudflare access session length for the control plane. the revoker handles removals; the session length is the ceiling on how stale an *added* claim can be before it's picked up, and on how long a revoker failure leaves someone in. one to four hours.

## 13. references

- `README.md` in this directory: the research synthesis and the reasoning behind each decision, with citations.
- `research/`: five raw research reports (workforce idps, active directory, self-hosted directories, relationship engines, app platforms and the two-population split).
- [#312](https://github.com/hackclub/auth/issues/312): "idp-like scoped oauth perms to access apps." closed by phase 2.
- [#348](https://github.com/hackclub/auth/issues/348): sign out everywhere (SAML SLO, Shared Signals/CAEP).
