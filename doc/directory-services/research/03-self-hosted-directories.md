# directory services survey: groups, OUs, delegation, exposure (self-hosted)

> raw research report, 2026-10-20. one of five inputs to `../README.md`.

## 1. Active Directory

**Object model (sketch)**

```
objects(dn, objectGUID, objectSid, objectClass, parent_container)   -- one tree (the DIT)
  ├─ organizationalUnit                                             -- containers; GPO + ACL inheritance scope
  ├─ user / computer (primaryGroupID → group RID)
  └─ group(groupType: security|distribution, scope: domainLocal|global|universal,
           member[] → dn)                                           -- forward link
  memberOf   = computed back-link of member (linkId 3, system-only, not in GC)
  tokenGroups = constructed attr: transitive SIDs incl. primary group
  nTSecurityDescriptor on every object (ACEs, inheritable)
  AdminSDHolder template → SDProp stamps protected objects hourly
```

**Nesting.** DAG, one edge type (`member`), cycles allowed. Scope rules constrain what can nest where: Universal may contain accounts/global/universal from any domain in the forest; Global only accounts and global groups from the *same* domain; Domain Local may contain accounts, global, universal from any trusted domain plus other DL groups from the same domain ([MS Learn, security groups table](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/understand-security-groups)). Effective membership is computed at logon into the PAC/token, recursively. `memberOf` is *not* effective membership: it is a computed back-link, omits the primary group, and "does not contain the user's membership in domain local and global groups in other domains" depending on which DC you ask ([MS, User Security Attributes](https://learn.microsoft.com/en-us/windows/win32/ad/security-properties); [linked attributes](https://learn.microsoft.com/en-us/windows/win32/ad/linked-attributes)). `tokenGroups` is the transitive SID set ([TokenGroups vs MemberOf](https://morgantechspace.com/2015/08/active-directory-tokengroups-vs-memberof.html)).

**Limits.** Two different ceilings: Kerberos `MaxTokenSize` (12,000 bytes pre-2012, 48,000 since; "more than 120 universal groups" blows the old default; `TokenSize = 1200 + 40d + 8s`; IIS caps at 48,000 because base64 in a 64 KB header) ([KB 327825](https://learn.microsoft.com/en-us/troubleshoot/windows-server/windows-security/kerberos-authentication-problems-if-user-belongs-to-groups)); and the LSA hard limit of 1,024 SIDs (~1,010 custom groups), `STATUS_TOO_MANY_CONTEXT_IDS`, not tunable ([KB 328889](https://support.microsoft.com/en-us/help/328889)). Practitioners: "depth is rarely the problem; fan-out is" ([windows-active-directory.com](https://www.windows-active-directory.com/understanding-group-nesting-limits-and-token-size.html)); the Member Of tab hides the nested groups that are nonetheless in the token ([JiJi](https://blog.jijitechnologies.com/active-directory-token-bloat)); SIDHistory from migrations doubles slots ([Manning, PFE chapter](https://livebook.manning.com/book/powershell-deep-dives/chapter-8)).

**OU vs group.** Microsoft is explicit: "The OU hierarchy does not need to reflect the departmental hierarchy… OUs are created for a specific purpose, such as the delegation of administration, the application of Group Policy, or to limit the visibility of objects," max recommended depth 10, and "The OU structure in AD DS is not intended to be visible to end users" ([Reviewing OU Design Concepts](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/plan/reviewing-ou-design-concepts)). OUs have no SID so can't appear in a DACL. Authz = groups; containment = OUs. Every AD admin eventually learns this by pain.

**Delegated admin.** ACEs on OUs, inherited down the subtree. The account-OU/resource-OU model has a "forest owner" delegating to "OU owners", with the rule that resource OU owners "cannot create child OUs" because "the creator or owner of an object has the ability to set the ACL on the object regardless of the permissions that are inherited from the parent" ([Delegating administration of account OUs](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/plan/delegating-administration-of-account-ous-and-resource-ous)). AdminSDHolder is the escape hatch that breaks it: SDProp runs every 60 min on the PDCE, disables inheritance on protected objects and resets their ACL ([Appendix C](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/plan/security-best-practices/appendix-c--protected-accounts-and-groups-in-active-directory)). Removing a user from Domain Admins leaves `adminCount=1` and inheritance off, so delegated OU permissions silently don't apply to them ([KB 817433](https://support.microsoft.com/en-us/topic/delegated-permissions-are-not-available-and-inheritance-is-automatically-disabled-56a70fa8-6d17-35ac-0f2c-87ec14b61980); [Reducing the AD attack surface](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/plan/security-best-practices/reducing-the-active-directory-attack-surface)).

**How apps learn groups.** LDAP bind + `memberOf`/`tokenGroups`, or the `LDAP_MATCHING_RULE_IN_CHAIN` filter `1.2.840.113556.1.4.1941` for transitive searches. Exposure is controlled by the bind account's read ACLs, which by default let any authenticated user read everything. The group owner has no say.

**SCIM.** None in AD DS itself (Entra Connect / Entra provisioning sit beside it).

**Populations.** Separate forests: organizational, resource, restricted-access ([Forest Design Models](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/plan/forest-design-models)). Trusts + SID filtering; cross-forest groups must be domain-local and universal groups inflate tokens.

**Verdict.** Right: groups-not-OUs for authz, precomputed transitive token, AGDLP role/resource split ([AGDLP](https://en.wikipedia.org/wiki/AGDLP)). Wrong: three scopes exist only for replication economics and leak into every design; `memberOf` lies; delegation via inherited ACEs is powerful and unauditable, and AdminSDHolder proves the designers didn't trust it either.

## 2. Generic LDAP / OpenLDAP

**Object model.**

```
groupOfNames(cn, member[] DN)          -- RFC 4519: member is MUST → no empty groups
groupOfUniqueNames(uniqueMember[])     -- "not what you think it is"; name+optional-UID syntax
posixGroup(gidNumber, memberUid[])     -- RFC 2307: STRUCTURAL, member is a *name*, not DN
  rfc2307bis: posixGroup becomes AUXILIARY on groupOfNames (draft, never an RFC)
memberOf                               -- NOT in base schema; overlay-maintained or dynlist-computed
groupOfURLs(memberURL)                 -- dynamic groups via dynlist
```

The empty-group problem is real: "it is not possible to create an empty group or to delete the last member… This leads to artificial tricks such as making every group a member of itself" ([groupOfEntries draft](https://datatracker.ietf.org/doc/html/draft-findlay-ldap-groupofentries-00)). `memberUid` can't carry DNs so posixGroup can't be dynamic or get memberOf ([OpenLDAP admin guide, dynlist](https://www.openldap.org/doc/admin26/overlays.html)).

**Nesting / memberOf.** `slapo-memberof` is write-time, "never replicated", consumers must run their own instance and exclude `memberOf` from syncrepl, and it does *not* do nested groups ([slapo-memberof(5)](https://www.openldap.org/software/man.cgi?query=slapo-memberof&sektion=5)). 2.5 deprecated it in favour of `dynlist` because refresh-mode replication can deliver the group before the member ([Symas, Replication and memberOf](https://www.symas.com/post/replication-and-memberof)); dynlist's `member+memberOf@groupOfNames*` gives recursive memberOf at read time ([slapo-dynlist(5)](https://www.openldap.org/software/man.cgi?query=slapo-dynlist&sektion=5)) but "significant processing done during the query… in certain cases, a very significant impact" (Symas), and "filtering on dynamic groups may return incomplete results if the search uses pagedResults" (man page). Howard Chu then un-deprecated memberof after fixing ordering with `memberof-addcheck` (ITS#10167) ([openldap-devel thread](https://lists.openldap.org/hyperkitty/list/openldap-devel@openldap.org/thread/2GPCBKOPH5KY6X36D74KED7STFW5JMAU/)). Symas's own migration guide back to write-time needs `autogroup` + a `nestgroup` overlay for nesting ([Symas KB](https://kb.symas.com/upgrade/migration-strategy-from-slapodynlist)). Lesson: the project itself flip-flopped on read-time vs write-time flattening; write-time (materialized) won on performance.

**OU vs group.** Both exist; the DIT hierarchy is mostly unused for authz. Red Hat DS planning docs: "Try to make the directory tree as flat as possible… The more hierarchical the directory tree, the more components in the names, and the more likely the names are to change," and renaming subtrees "is resource-intensive and long" ([RHDS 12, Designing the directory tree](https://docs.redhat.com/en/documentation/red_hat_directory_server/12/html/planning_and_designing_directory_server/designing-the-directory-tree_designing-rhds)).

**Delegated admin.** `access to <what> by <who> <access>`; group delegation looks like `by set="[cn=groupadmins,ou=group,dc=x]/member* & user" write` or `by dnattr=owner write`. First matching `<what>` wins, each clause ends with implicit `by * none`, rootdn bypasses everything ([OpenLDAP access control](https://www.openldap.org/doc/admin26/access-control.html)). Ordering bugs are the classic failure mode. Inheritance down a subtree works via `dn.subtree=`, which is why people build OU trees they then regret.

**Exposure.** Whatever the bind DN's ACLs allow; usually "authenticated users read everything". No per-app shaping without a proxy.

**SCIM.** None. **Populations.** Separate suffixes/databases or separate servers; ACLs to wall them off.

**Verdict.** Schema is broken in standard ways (MUST member, three group classes, memberOf not standard). The only thing everyone agrees on: flat DIT, `groupOfNames` + auxiliary posixGroup, materialized memberOf.

## 3. FreeIPA

**Object model.** Flat DIT on 389-ds: `cn=users,cn=accounts,$SUFFIX`, `cn=groups,cn=accounts,$SUFFIX`, hosts, hostgroups, services ([FreeIPA HowTo/LDAP](https://www.freeipa.org/page/HowTo/LDAP)). Groups are `groupOfNames` + `ipaUserGroup` (+ `posixGroup` if POSIX); types POSIX, non-POSIX, external (AD SIDs). Plus:

```
hbacrule(users|groups, hosts|hostgroups, services, enabled)      -- allow-only
permission(target: --type|--memberof|--targetgroup|--filter|--subtree, rights, attrs) → generated ACI
privilege(member permissions)
role(member privileges; members: users|groups|hosts)
automemberrule(type, inclusive/exclusive regex)
group.memberManager[] → user|group DN                            -- delegated membership
```

**Nesting.** DAG via `member`; `memberOf` maintained by the 389-ds memberOf plugin, transitive. Nested child groups need `extensibleObject` or you get objectClass violations. Performance is the documented sore point: "with a total of 10000 leafs creating 400 nested groups triggered 14M internal searches" ([389-ds MemberOf scalability](https://www.port389.org/docs/389ds/design/memberof-scalability.html)); a 500k-entry import + fixup ran "about 20 hrs (still not completed)" ([issue 49031](https://pagure.io/389-ds-base/issue/49031/)); mitigations are `memberOfSkipNested` (breaks nested correctness), deferred updates (non-atomic, needs fixup on crash), and group scoping ([deferred update design](https://www.port389.org/docs/389ds/design/deferred-memberof-update.html)). Large group updates can "freeze (in read and in write) a large portion of the database".

**OU vs group.** No OUs. Containers are fixed per object type. Hostgroups + HBAC do what AD does with OUs + GPO.

**Delegated admin.** Three layers. (1) RBAC: permission → privilege → role, with `--memberof=<group>` turning into a `(memberOf=...)` target filter so a role can manage "users in group X" ([Permissions V2](https://www.freeipa.org/page/V4/Permissions_V2)). (2) Member managers (4.8.4+): "a principal that is able to manage members of a group… cannot modify additional attributes of a group", stored in indexed `memberManager`, users or groups, "independent from members" ([membermanager design](https://freeipa.readthedocs.io/en/ipa-4-11/designs/membermanager.html)). (3) Self-service/delegation rules for attributes. HBAC is allow-only: disable `allow_all` without replacements and "immediately any access of existing users to existing hosts will be denied" ([HBAC and allow_all](https://www.freeipa.org/page/Howto/HBAC_and_allow_all)). Automember rebuild "only adds new membership relationship, it does not remove" ([Automember rebuild](https://www.freeipa.org/page/V4/Automember_rebuild_membership)).

**Exposure.** LDAP; system accounts under `cn=sysaccounts,cn=etc` bind and read per ACI. Group owner has no control over exposure.

**SCIM.** None native. **Populations.** AD trusts + ID views for "the other" population; FreeIPA is squarely a workforce directory.

**Verdict.** Member managers are the cleanest delegated-membership primitive in the survey (one attribute on the group, members-only). RBAC's `--memberof` targeting is the right idea (group-defined scope, not tree-defined). The 389 memberOf plugin shows what write-time flattening costs at scale without a closure table.

## 4. Kanidm

**Object model.** Everything is an entry with a UUID; no tree.

```
entry(uuid, class[], name, spn, ..., memberof[] (computed), directmemberof (internal))
group(member[] → uuid, entry_managed_by → group|account uuid)
access_control_profile(receiver: group ONLY, targetscope: filter|self, attrs, classes)
oauth2_rs(scope_map: group→scopes, sup_scope_map, claim_map: group→claim)
```

**Nesting.** DAG via `member`; `memberof` is precomputed by a post-write plugin. The design doc is explicit about *why* the edge lives on the group: "There is a security benefit to the relationship of 'groups have members' rather than 'users are members of groups'. That benefit is delegated administration" — Claire with write on "library users" can only add people to that one group ([memberof design](https://raw.githubusercontent.com/kanidm/kanidm/master/book/src/developers/designs/memberof.rst)). Cycles are tolerated by the fixpoint ("entry pre:memberOf == entry post:memberOf" terminates). `directmemberof` exists but isn't exposed because "If you can read memberof, that's the super-set" ([discussion 3020](https://github.com/kanidm/kanidm/discussions/3020)).

**OU vs group.** No OUs, deliberately. LDAP gateway design: "All entries are presented in a flat scope, the same as Kanidm to avoid trying to 'create' a fake hierarchy" ([ldap_gateway design](https://raw.githubusercontent.com/kanidm/kanidm/master/book/src/developers/designs/ldap_gateway.rst)); the LDAP chapter: "relying more on the Kanidm query and filter system rather than attempting to generate a tree-like representation… As almost all clients can use filters for entry selection we don't believe this is a limitation" ([LDAP integration](https://kanidm.github.io/kanidm/stable/integrations/ldap.html)).

**Delegated admin.** Two mechanisms. ACPs where "receiver… Can *only* be a group" and target is a filter ([access profiles original](https://raw.githubusercontent.com/kanidm/kanidm/master/book/src/developers/designs/access_profiles_original.md)); the 2022 rework moves toward group-targeted ACPs because filter evaluation was "nearly 35% of the time taken in a search operation" and dynamic groups must not use `memberof` ("infinite churn") ([access profiles rework 2022](https://kanidm.github.io/kanidm/stable/developers/designs/access_profiles_rework_2022.html)). And `entry_managed_by`: a group (or user — they kept users for small deployments, [issue 2624](https://github.com/kanidm/kanidm/issues/2624)) that may modify the group, settable at creation by `idm_group_admins` but afterwards "may only be modified by members of `idm_access_control_admins`" ([Groups](https://kanidm.github.io/kanidm/stable/accounts/groups.html)). Separation of duties is baked in via distinct builtin groups (group admins, person admins, access-control admins, oauth2 admins) and an `idm_high_privilege` taint ([access control defaults](https://raw.githubusercontent.com/kanidm/kanidm/master/book/src/developers/designs/access_control_defaults.md)). No containment inheritance because there is no containment.

**Exposure.** LDAP is read-only ("The structure of LDAP is too simplistic for writing"); DNs are generated from spn/name/uuid under a `dc=` suffix; bound accounts get only anonymous read rights unless they bind with a service-account token ([LDAP integration](https://kanidm.github.io/kanidm/stable/integrations/ldap.html)). OAuth2: per-client scope maps (group → scopes), supplementary scope maps, claim maps (group → claim value), configured by `idm_oauth2_admins` ([OAuth2](https://kanidm.github.io/kanidm/stable/integrations/oauth2.html)). Group-granular, but configured on the app side by an oauth2 admin, not by the group's manager.

**SCIM.** Full SCIM API since 1.7.0 with access control; the "sync only" line in Supported Features is stale ([issue 4638](https://github.com/kanidm/kanidm/issues/4638)). **Populations.** Single domain per server; no tenancy.

**Verdict.** The most coherent model here: one object type, UUIDs, one edge type, materialized memberof, group-only receivers, per-entry manager. The costs: no multi-tenant story, LDAP is a projection not a store, and dynamic groups are deliberately crippled to stay sound.

## 5. Keycloak

**Object model.**

```
realm
  group(id, name, parent_id)               -- tree, single parent, path "/a/b"
  group_attributes, group_role_mapping
  realm_role / client_role(client_id)      -- composite_role(parent, child) DAG
  user_group_membership, user_role_mapping
  client → client_scope → protocol_mapper  -- e.g. oidc-group-membership-mapper(full.path)
  organization(domains, members, idps)     -- 25+
  admin-permissions client (FGAP v2)       -- resources: Users/Groups/Clients/Roles, scopes
```

**Nesting.** Groups are a strict tree; "Users that become members of a group inherit the attributes and role mappings that group defines", and subgroups inherit from parents ([Server Admin Guide](https://www.keycloak.org/docs/latest/server_admin/index.html)). Roles nest as a DAG (composites). Perf history: "starting with a few thousand groups, operations that rely on getTopLevelGroupsStream… are getting really slow" ([#19923](https://github.com/keycloak/keycloak/issues/19923)); ~18k flat groups made a user's Groups tab take ~5 minutes ([#20489](https://github.com/keycloak/keycloak/issues/20489)); subgroup pagination had to be pushed into the storage layer ([#22372](https://github.com/keycloak/keycloak/issues/22372)).

**Groups vs roles.** Keycloak admits the blur: "Groups are just a collection of users that you can apply roles and attributes to in one place. Roles define a type of user… Use groups to manage users. Use composite roles to manage applications and services" ([Groups vs Roles](https://wjw465150.gitbooks.io/keycloak-documentation/content/server_admin/topics/groups/groups-vs-roles.html)). The 2015 dev thread conceded "with composite roles, you can have a role act as a group" ([keycloak-dev](https://lists.jboss.org/pipermail/keycloak-dev/2015-November/005735.html)); the 2025 discussion still has users saying "using Group was enough" ([#36325](https://github.com/keycloak/keycloak/discussions/36325)). The useful heuristic from Phase Two: "If you are about to create a role named after a team, you wanted a group. If you are about to create a group named after a permission, you wanted a composite role" ([phasetwo](https://phasetwo.io/tutorials/authorization/roles-and-groups/)).

**Delegated admin.** FGAP v2 (26.2+): per-group scopes `manage, view, manage-members, view-members, manage-membership`; "`manage-members`… applies to any child group in the group hierarchy. This can be prevented by explicitly denying permission for specific subgroups" ([RHBK 26.2 admin permissions](https://docs.redhat.com/en/documentation/red_hat_build_of_keycloak/26.2/html/server_administration_guide/admin_permissions); [FGAP blog](https://www.keycloak.org/2025/05/fgap-kc-26-2)). Already one semantic hole: group-level denies don't block `manage-group-membership` because that scope has no alias to Groups ([#46693](https://github.com/keycloak/keycloak/issues/46693)). V1 couldn't inherit to subgroups at all ([#16915](https://github.com/keycloak/keycloak/discussions/16915)).

**Exposure.** Entirely app-side: a client scope with a Group Membership mapper (optionally full path) decides what goes in the token. The group owner has no control; default is "all groups the user is in".

**SCIM.** For years "Keycloak currently does not support SCIM" ([#13484](https://github.com/keycloak/keycloak/issues/13484)); 26.6 ships an experimental SCIM *server* (/Users, /Groups), supported in 26.8; outbound client still third-party ([blog](https://www.keycloak.org/2026/04/scim-as-experimental-feature)).

**Populations.** Realms are hard isolation (separate users, roles, clients). Organizations (25+) add B2B tenancy *inside* a realm with per-org IdPs and an `organization` claim ([announcement](https://www.keycloak.org/2024/06/announcement-keycloak-organizations)). Staff realm + customer realm is the standard answer and works; what breaks is anything needing cross-realm admin or shared clients.

**Verdict.** Two overlapping nesting primitives (group tree, role DAG) plus client roles is the source of the confusion. FGAP v2 is a good delegated-admin design arriving ten years late. Realm separation is exactly right for your two populations.

## 6. Authentik

**Object model.**

```
group(pk uuid, name, parent_id, is_superuser, attributes json, roles[])
role(permissions[])                          -- global or object-level (Django perms)
policy_binding(target: application|flow|..., group|user|policy, order)
property_mapping(expression) → scope mapping / LDAP / SCIM / SAML
application_entitlement(app, name)  bound to users/groups; exposed via `entitlements` scope
provider: oauth2 | saml | ldap(outpost) | scim(backchannel) ; source: ldap | scim | oauth
```

**Nesting.** Tree via `parent`, but the direction is the *opposite* of Kanidm/AD: "Members of children groups are effective members of the parent group… Recursion is limited to 20 levels to prevent deadlocks" ([Groups](https://docs.goauthentik.io/docs/users-sources/groups/)). Cycles used to make "a DB worker running forever at 100% CPU" ([#3116](https://github.com/goauthentik/authentik/issues/3116)); recursive membership was "handled very inconsistently" until the 2023.8 rework ([release notes](https://docs.goauthentik.io/releases/2023.8/)); a PR to allow multiple parents is pending ([#17671](https://github.com/goauthentik/authentik/issues/17671)). Attributes merge recursively. Roles "are also inherited through group hierarchy" ([Roles](https://docs.goauthentik.io/docs/users-sources/roles/)).

**OU vs group.** No OUs; "user path" is a cosmetic string.

**Delegated admin.** Object-level permissions on a specific group ("the object permission to change only the Default Authentication flow will not be able to change any other flow"), assigned to roles/users ([Permissions](https://docs.goauthentik.io/docs/users-sources/access-control/permissions/)). No containment inheritance of those object perms is documented.

**Exposure.** App-side: scope mappings on the provider; default `profile` scope "Includes basic profile information, such as the user's username, name, and group membership" — i.e. all groups ([OAuth2 provider](https://docs.goauthentik.io/docs/add-secure-apps/providers/oauth2/)). Entitlements are "scoped to a single application and can be bound to multiple users and/or groups" ([Manage apps](https://docs.goauthentik.io/docs/add-secure-apps/applications/manage_apps/)) — closest thing to a per-app group→claim table, but still configured by the app admin. LDAP provider emits `ou=users`, `ou=groups`, `ou=virtual-groups`, `memberOf` on users *and* groups, with a "Search full LDAP directory" permission gating whether a binder sees more than itself ([LDAP provider](https://docs.goauthentik.io/docs/add-secure-apps/providers/ldap/)).

**SCIM.** Both directions. Outbound: "only users who are bound to that application are synchronized" — but "If no users are bound to the SCIM application, the SCIM provider synchronizes all users" (footgun), group filters per provider, and nested groups aren't flattened in what's pushed ([SCIM provider](https://docs.goauthentik.io/docs/add-secure-apps/providers/scim/); [#15009](https://github.com/goauthentik/authentik/issues/15009)). Inbound SCIM source: DELETE "removes the underlying authentik User or Group object" ([SCIM source](https://docs.goauthentik.io/docs/users-sources/sources/protocols/scim/)).

**Populations.** Single tenant; brands only change look/flows. Separation is by policy, not by store.

**Verdict.** App-bound provisioning (bind a group to the app → that's who gets SCIM'd) is the right instinct and maps directly onto your `app_groups`. The parent-tree with inverted semantics and a cycle bug is a cautionary tale for anything that isn't an explicit edge table.

## 7. Zitadel

**Object model.**

```
instance → organization → project → application
project_role(project, key, display_name, group)       -- "group" here is just a UI bucket
project_grant(project, granted_org, roles[])           -- B2B delegation of role *assignment*
user_grant(user, project|project_grant, roles[])       -- "authorization"
member(instance|org|project|project_grant, user, manager_role)  -- IAM_OWNER, ORG_OWNER, PROJECT_OWNER, PROJECT_GRANT_OWNER, ORG_USER_MANAGER…
group(org, name)  -- new, flat, org-scoped (issue #9702, closed June 2026)
```

**Nesting.** None historically; roles are flat per project. User groups shipped in 2026 as flat, org-unique, with "group roles" in tokens "only if the requesting application asks for the 'group scope'" ([#9702](https://github.com/zitadel/zitadel/issues/9702); requested since 2021, [#2134](https://github.com/zitadel/zitadel/discussions/2134)).

**OU vs group.** Orgs are the container (tenant), projects are the authz namespace. No OUs.

**Delegated admin.** Manager roles at each level; project grants let a partner org "manage the role assignments of their own users for your project" with the grantor choosing which roles are grantable ([Projects](https://zitadel.com/docs/concepts/structure/projects); [Granted projects](https://zitadel.com/docs/concepts/structure/granted_projects); [Administrators](https://zitadel.com/docs/guides/manage/console/administrators)). Config is clean because the hierarchy is fixed and shallow.

**Exposure.** Roles are owned by the project (the app side); tokens carry `urn:zitadel:iam:org:project:roles` as `{role: {orgId: primaryDomain}}` when "assert roles on authentication" is on; "check authorization on authentication" can refuse login without a role ([claims](https://zitadel.com/docs/apis/openidoauth/claims)).

**SCIM.** Inbound SCIM v2 server at `/scim/v2/{orgId}` (preview, 1000-request cap then licensed); outbound client in development ([#8140](https://github.com/zitadel/zitadel/issues/8140), [#6601](https://github.com/zitadel/zitadel/issues/6601)).

**Populations.** Orgs are the tenancy primitive, designed for exactly staff-org vs customer-orgs with project grants across them.

**Verdict.** Right that roles belong to the resource (project) and that cross-tenant delegation is "you may assign these roles to your own people". Wrong (for a long time) that groups weren't needed; they caved.

## 8. LLDAP and Authelia (brief)

**LLDAP**: `cn=x,ou=people,<base>` and `cn=g,ou=groups,<base>`, `memberOf` filters supported, three built-in admin groups (`lldap_admin`, `lldap_password_manager`, `lldap_strict_readonly`), no nested groups, no custom OUs, "The goal is *not* to provide a full LDAP server" ([README](https://github.com/lldap/lldap)). It's an existence proof that a flat two-OU read-mostly LDAP view satisfies Nextcloud/Jellyfin/Gitea/etc.

**Authelia** (a consumer): `groups_filter` with `{dn}`/`{username}` placeholders, `group_search_mode: filter | memberof`, per-implementation defaults for AD/FreeIPA/LLDAP/rfc2307bis, and the AD recursive filter `(&(member:1.2.840.113556.1.4.1941:={dn})(objectClass=group))` ([LDAP config](https://www.authelia.com/configuration/first-factor/ldap/)); access rules match `group:<name>` ([access control](https://www.authelia.com/configuration/security/access-control/)). Tells you what an LDAP projection must answer: both "members of group G" (`member=dn`) and "groups of user U" (`memberOf`).

## Comparison

| | Nesting | Containment | Effective membership | Delegated admin | Exposure controlled by | SCIM | Populations |
|---|---|---|---|---|---|---|---|
| AD | DAG, `member`, cycles OK, 3 scopes | OUs (GPO/ACL only) | PAC/tokenGroups at logon; memberOf is partial | Inherited ACEs on OUs; AdminSDHolder overrides | Bind ACLs (default: everything) | No | Forests + trusts |
| OpenLDAP | DAG by convention; memberof overlay no nesting, dynlist `*` yes | DIT (discouraged) | write-time overlay or read-time dynlist | `access … by set/group/dnattr`, order-sensitive | Bind ACLs | No | Suffixes/servers |
| FreeIPA | DAG, `member` | Fixed containers | 389 memberOf plugin (expensive) | RBAC `--memberof`, memberManager, HBAC | ACIs | No | AD trust |
| Kanidm | DAG, `member`, cycles tolerated | None | post-write `memberof` plugin | `entry_managed_by` + group-receiver ACPs | oauth2 admins per client/group | Yes (API) | Single domain |
| Keycloak | Group tree + role DAG | Realm, group path | Inherited at mapping time | FGAP v2 scopes, inherit to subgroups w/ deny | Client mappers | Server 26.6+ | Realms, Organizations |
| Authentik | Parent tree (child ⊂ parent), 20 levels | None | Recursive CTE | Object perms on group | Provider mappings; entitlements per app; app binding for SCIM | In + out | Single tenant |
| Zitadel | Flat (groups 2026) | Instance/org/project | n/a | Manager roles, project grants | Project owns roles; per-app assert | In (preview) | Orgs |
| LLDAP | None | ou=people/ou=groups | direct only | 3 fixed admin groups | Bind | No | No |

## Lessons for the draft model

**(a) Read-only LDAP over a DAG, flat `ou=people` + `ou=groups` with `memberOf` — workable, and it's what the modern ones do.** Kanidm, LLDAP, and authentik all serve precisely this shape; Kanidm's stated reason is that filters replace hierarchy and "almost all clients can use filters". Specifics that will bite:
- Emit `memberOf` as the *transitive* closure from `effective_memberships` (Kanidm does; AD doesn't and everyone writes recursive-filter workarounds for it). Emit `member` on groups too — Authelia's default `filter` mode searches `(member={dn})`, not `memberOf`. Decide whether `member` is direct or transitive and document it; Kanidm keeps member direct and memberOf transitive, which is the least surprising.
- Use `groupOfNames` + auxiliary `posixGroup` (rfc2307bis style). Because you generate the entries, you can ignore the MUST-member rule and serve empty groups; note it in docs since strict clients may choke.
- Generate DNs from a stable key. Kanidm accepts `name=`, `spn=`, or `uuid=` RDNs; Red Hat's whole flat-DIT argument is that renames break DNs. Expose a UUID attribute (`entryUUID`) and accept uuid-RDN binds.
- Bind-account semantics: Kanidm gives binders anonymous-equivalent rights unless they present a service token; authentik gates with a "search full directory" permission. Your `app_groups` suggests a third option: the bind account for app X sees only the groups exposed to X. That's novel but coherent. The one thing not to do is AD's "which DC you asked changes the answer".
- Pagination and dynamic evaluation are non-issues because you materialize; the dynlist `pagedResults` caveat is exactly the trap you avoid.

**(b) Single-edge-type nesting is what the good ones do.** AD, FreeIPA/389, OpenLDAP and Kanidm all have exactly one edge (`member`) whose target may be a person or a group, and compute `memberOf` as a derived, materialized attribute. The two products that used a `parent_id` tree instead (Keycloak, authentik) both accumulated pain: Keycloak's path-based lookups fell over at thousands of groups and FGAP had to special-case subtree inheritance; authentik had cycles pegging CPU, inverted semantics ("children are members of the parent"), and is now adding multi-parent. Zitadel went flat and spent four years being asked for groups. Your DAG + closure table is the right shape. Three refinements:
- Keep a `direct` flag (or keep `memberships` and `effective_memberships` separate, as you have); Kanidm regrets not exposing `directmemberof`.
- Rejecting cycles at write is fine (Kanidm and AD tolerate them via fixpoint; authentik caps depth). Simpler to forbid.
- The AD lesson is fan-out, not depth: effective-group counts per user are what blow up tokens and PACs. For 150 staff this is irrelevant, but if you ever emit `groups` claims by default (authentik's `profile` does), you reinvent token bloat for OIDC. Make group claims opt-in per app — which `app_groups` already does.
- Kanidm's design note is worth carrying over verbatim: the edge lives on the group, not the person, *because* that's what makes delegation safe. Your `memberships(group, member)` row should be authorized against the group, never the member.

**(c) Delegated admin in the good ones is "a group that manages this group", not tree inheritance.**
- FreeIPA `memberManager`: users or groups, add/remove members only, no attribute rights.
- Kanidm `entry_managed_by`: one group per entry; *changing the manager* needs a different, higher privilege (`idm_access_control_admins`). That split — managing members vs. managing who manages — is the thing AD's ACL model gets wrong (owner can reset the ACL, hence the "resource OU owners may not create OUs" rule and AdminSDHolder).
- Keycloak FGAP v2: explicit scope vocabulary (`view`, `manage`, `view-members`, `manage-members`, `manage-membership`) and subtree inheritance with explicit deny — and the first bug was a scope that didn't alias through.

Your `grants(grantee_group, permission, target_group, recursive?)` is a generalization of all three. Concretely:
- Split `permission` into at least `manage_members`, `manage_group` (name/attrs), `manage_grants` (who else can manage), and `expose` (create `app_groups` rows). Kanidm/FreeIPA both show that "manage members" is the 90% case and should not imply the others.
- Define `recursive` carefully. There is no containment tree in a DAG; "recursive" can only mean "also applies to groups reachable via `member` edges from the target" (sub-groups). Since a sub-group can have several parents, a group may be manageable through several grants. That's fine, but do not add deny semantics on top — Keycloak needed denies only because the tree forced over-granting, and denies in a DAG with multiple paths are where #46693-style holes come from.
- Watch escalation through nesting: if Claire manages `library-users` and someone nests `library-users` into `admins`, Claire now controls admin membership. Adding group A as a member of group B must require `manage_members` on B *and* should be treated as handing A's managers power over B. Mark your high-privilege groups `protected` (Kanidm's `idm_high_privilege` taint is the sane version of AdminSDHolder) and refuse grants targeting them, and refuse nesting a delegated group into them.
- On `app_groups` as "the only way an app learns about a group, exposed by the group's manager": nobody does exactly this. Everyone configures exposure on the app side (Keycloak mappers, authentik scope mappings, Kanidm claim maps by oauth2 admins, Zitadel project roles). The closest precedents are authentik's "bind the group to the application → those users get provisioned" and Kanidm's per-group scope/claim maps. Your inversion is defensible — it's the only one that gives a group owner a say and prevents an app from vacuuming the whole directory — but it will need an "expose" permission grantable to platform admins too, or app onboarding stalls on every group manager. The `required?` flag maps cleanly to authentik's app access binding and Zitadel's "check authorization on authentication".

**Populations.** Every product that handles staff vs. customers well does it with a hard boundary: separate forest (AD), separate realm (Keycloak), separate org (Zitadel). Products that don't have a boundary (authentik, Kanidm) make you do it with policy. Your "50k community users are simply not in the directory" is the forest/realm answer, and it's right — the LDAP view and SCIM targets should be derived from a staff-scoped person set, not from a global `users` table with a per-query filter, so that there is no path by which a community user acquires a DN.
