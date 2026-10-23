# how commercial workforce IdPs model groups / OUs / directory

> raw research report, 2026-10-20. one of five inputs to `../README.md`.

## 1. okta (workforce identity cloud)

**object model (pseudo-tables)**

```
users(id, profile{...}, status, realm_id)            -- realm_id optional, OIG/ADM sku
groups(id, type: OKTA_GROUP|APP_GROUP|BUILT_IN, profile{name,...}, source_app_id?)
group_memberships(group_id, user_id)                  -- users only. NO group->group edge
group_rules(id, condition_expr, assign_to_group_ids[≤100], excluded_user_ids[≤100])
apps(id, sign_on_mode, provisioning_settings)
app_user_assignments(app_id, user_id, scope: USER|GROUP, profile{}, source_group_id?)
app_group_assignments(app_id, group_id, priority, profile{})   -- "assign app to group"
push_group_mappings(app_id, okta_group_id, target_group_id)    -- separate from assignment!
admin_role_bindings(principal: user|group|client_app, role, resource_set_id)
resource_sets(id, resources[≤1000] of users|groups|apps|realms)
realms(id) ; realm_assignments(rule_expr -> realm_id)         -- users only
(OIG) entitlements, bundles, grants(user, entitlement|bundle), resource_owners(group|app|entitlement, user[≤10])
```

**nesting:** flat. okta's own doc: "Okta doesn't support nested groups. Okta imports all nested directories for group members and adds the user to each group in Okta" — AD hierarchy is flattened at import time ([How does Okta handle nested groups](https://support.okta.com/help/s/article/How-does-Okta-handle-nested-groups), [import groups from AD](https://help.okta.com/oie/en-us/content/topics/directory/ad-agent-import-groups.htm)). the sanctioned workaround is group rules, and rules can't chain: "IF isMemberOfGroupName('California') THEN 'West Coast'" won't fire off another rule's output; you write one rule that assigns both targets ([group rule limitations](https://support.okta.com/help/s/article/okta-group-rule-limitations-and-restrictions)). limits: 2,000 rules/org, 100 target groups per rule, unlimited groups per org ([limits](https://support.okta.com/help/s/article/groups-group-push-and-group-rules-limits)). effective membership is therefore just direct membership — there's no memberOf/transitive concept because there's nothing to be transitive over.

**OU vs group:** no OUs. realms (2024+) are the closest thing, and they're explicitly user-only: "Users must belong to a realm, but groups and apps exist independently of realms. Groups, apps, servers, and devices can't be scoped to a particular realm." group rules also can't be realm-scoped. limits: 5,000 realms, 500 realm assignments ([realms requirements](https://help.okta.com/oie/en-us/content/topics/users-groups-profiles/realms/realms-requirements.htm)). so okta has one partitioning axis (realm) for admin scoping and one for access (groups), and they don't compose — a realm admin gets group management by having specific groups listed in their resource set ([IAMSE on realm admins](https://iamse.blog/2025/01/22/assigning-administrators-to-realms-in-okta/)).

**dynamic groups:** group rules on okta expression language. complaints: must deactivate rule to edit conditions; target group edits only became possible in release 2026.07; rules can't target admin groups; the "no chaining" rule forces you to encode the hierarchy into every leaf rule (gitlab's handbook shows exactly this — one department rule assigning `dept.*`, `div.*`, and `app.*` groups simultaneously: [gitlab okta groups](https://handbook.gitlab.com/handbook/security/corporate/systems/okta/group/)).

**delegated admin:** standard roles (group admin, group membership admin) + custom roles bound to resource sets. the resource-set model is genuinely good: "admin + role + resource set", up to 10,000 resource sets × 1,000 resources ([custom admin roles](https://help.okta.com/oie/en-us/content/topics/security/custom-admin-role/custom-admin-roles.htm)). the gotcha everyone hits: any group that has an admin role assigned becomes super-admin-only — "If a group admin is assigned access to a group that is later assigned an admin role, the group admin will no longer be able to make any changes" ([support](https://support.okta.com/help/s/article/group-membership-administrator-unable-to-modify-group)). also "group owners" (OIG) carry *zero* permissions — "group owners have no default permissions… If you want them to perform admin actions like adding and removing users… assign them an appropriate Okta admin role" ([group ownership](https://help.okta.com/en-us/Content/Topics/identity-governance/group-owner.htm)). ownership is an approval-routing concept, not an authority.

**app assignment + claims:** app admin assigns the app to groups (or users). group assignment carries a per-group app profile and a priority; a user in multiple assigned groups gets the highest-priority group's profile, or merged array attributes with "combine values across groups" ([assign group priority](https://help.okta.com/en-us/content/topics/users-groups-profiles/usgp-assign-app-group-priority.htm)). individual assignment "overrides group" and is sticky. the groups *claim* is a separate, app-side filter: "Starts with / Equals / Contains / Matches regex" on the OIDC app's sign-on tab (org authz server only) or an expression on a custom authz server ([groups claim guide](https://developer.okta.com/docs/guides/customize-tokens-groups-claim/main/)). the app-side filter is a text match on *group name*, not on assignment — which is why practitioners prefix groups (`app.gitlab.*`) so the filter works. hard cap: `Groups.*` functions max 100 groups per claim; exceed it and the token isn't issued ("The groups claim matched too many groups" — [support](https://support.okta.com/help/s/article/error-the-groups-claim-matched-too-many-groups-and-must-be-configured-to-match-fewer-groups), [okta-auth-js#1031](https://github.com/okta/okta-auth-js/issues/1031)). exposure control: the app admin decides, by regex. the group's manager has no say.

**SCIM:** user provisioning scope = users assigned to the app (directly or via assigned groups). group push is a *separate* mapping and okta says don't reuse the assignment group: "Okta doesn't support using the same group for app assignment and Group Push" ([optimizely doc quoting okta](https://support.optimizely.com/hc/en-us/articles/24494074021261-Create-a-SCIM-provisioning-app-in-Okta)). pain: "Push Now" is a full overwrite; deactivated users linger in pushed memberships ([devforum](https://devforum.okta.com/t/scim-group-push-includes-disabled-users/31389)); wizard-built connectors default to PUT and silently fail against PATCH-only targets ([cisco secure access article](https://support.okta.com/help/s/article/okta-group-push-fails-to-sync-memberships-to-cisco-secure-access-via-custom-scim-2-0-integration)).

**populations:** two products, two tenants. WIC for employees, CIC (auth0) for customers — "separate dashboards, separate APIs, separate SDKs, and separate billing"; "Workforce Universal Directory is not your customer profile store" ([ssojet](https://ssojet.com/blog/okta-workforce-identity-vs-customer-identity-saas-vendors)). realms are intended for partner/contractor partitions *inside* workforce, not for B2C.

**verdict:** right — flat groups + resource sets + explicit app↔group assignment with per-group profiles is a clean, predictable model. wrong — the assignment/push/claim split means one "team" is three groups; the groups claim is a name-regex rather than derived from assignment; the 100-group claim cap; group owners that own nothing; realms bolted on without touching groups.

## 2. microsoft entra id

**object model**

```
users(id, userType: Member|Guest, ...)
groups(id, groupTypes[Unified?], securityEnabled, mailEnabled, membershipType: Assigned|DynamicUser|DynamicDevice,
       membershipRule, isAssignableToRole, disableNesting, owners[≤100])
group_members(group_id, member: user|group|device|servicePrincipal)  -- DAG, security groups only
servicePrincipals(id, appRoles[], appRoleAssignmentRequired, owners[≤100 users])
appRoleAssignments(principal: user|group|SP, resource_sp_id, appRoleId)   -- "assign group to app"
administrativeUnits(id, members: users|groups|devices, isMemberManagementRestricted, membershipRule?)
roleAssignments(principal, roleDefinition, directoryScope: tenant|AU|object)
(governance) catalogs, accessPackages(resourceRoles: group member|app role|site), policies, assignments
```

**nesting:** security groups nest (DAG, arbitrary depth); M365 groups never nest in either direction ("Because Microsoft 365 groups cannot contain other groups, membership in a Microsoft 365 group is always direct" — [checkMemberGroups](https://learn.microsoft.com/en-us/graph/api/directoryobject-checkmembergroups?view=graph-rest-1.0)); role-assignable groups can't nest. graph exposes `memberOf`, `transitiveMemberOf`, `transitiveMembers`, `getMemberGroups`, `checkMemberGroups` (max 20 ids/request). new `disableNesting` flag per security group ([office365itpros](https://office365itpros.com/2026/08/03/blocking-for-nested-security-groups/)). the official limits page is the key document — nesting is "supported" for claims, conditional access, SSPR, device-join, and *not* for "App role assignment, for both access and provisioning", group-based licensing, M365 groups. plus: 2,048 total memberships before access "might be blocked"; 150 groups in SAML / 200 in JWT then overage; CA evaluates 4,096; filtering only works ≤1,000 groups ([service limits](https://learn.microsoft.com/en-us/entra/identity/users/directory-service-limits-restrictions)). so the same group graph is transitive for tokens and *non*-transitive for assignment/provisioning. this is the single most common entra surprise.

**OU vs group:** no OUs in the AD sense. administrative units are admin-scoping containers, not policy containers: can't nest, members only users/groups/devices, adding a group to an AU delegates the group's *properties* not its *members*, dynamic groups can't be added to AUs, dynamic AUs are single-type ([AU docs](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/administrative-units)). restricted-management AUs (max 100) block even global admins — useful for exec protection, flagged by datadog as a persistence vector ([datadog security labs](https://securitylabs.datadoghq.com/articles/abusing-entra-id-administrative-units/)). there's also the 4-way group-type confusion (security / M365 / mail-enabled security / distribution; the last two managed only in exchange admin center — [learn about groups](https://learn.microsoft.com/en-us/entra/fundamentals/concept-learn-about-groups)).

**dynamic groups:** rule language over user/device attributes; 15,000 dynamic groups/tenant. processing is tenant-sequential: "may take more than 24 hours depending on… tenant size, group size, number of attribute changes, rule complexity, and operator choice"; `memberOf` rules "slow dynamic membership processing for every group in a tenant" and are being retired 3 nov 2026 ([troubleshooting](https://learn.microsoft.com/en-us/troubleshoot/entra/entra-id/dir-dmns-obj/troubleshoot-dynamic-group-processing), [ourcloudnetwork](https://ourcloudnetwork.com/the-memberof-rule-operator-is-ending-for-dynamic-groups-in-entra/)). microsoft ships a "pause all groups" script as mitigation. practitioners have learned not to promise anything is instant.

**delegated admin:** group owners manage membership of their own assigned groups (not dynamic ones); AU-scoped directory roles for user/group *objects*; custom roles (100/tenant). the actually-good delegation story is entitlement management: catalog creators → catalog owners add resources (groups, app roles, sites) → access package managers build packages over those resources but "can't add resources to a catalog" ([delegation roles](https://learn.microsoft.com/en-us/entra/id-governance/entitlement-management-delegate)). that's a real two-sided grant: resource owners contribute, package managers compose. hated: P1/P2 licensing for AUs and group-based app assignment; AUs don't delegate membership; the "users can create security groups = Yes" default and its all-or-nothing toggle ("You can't specify individuals who can create their own groups" — [self-service groups](https://learn.microsoft.com/en-us/entra/identity/users/groups-self-service-management)), which CIS/scubagear want flipped ([scubagear#1770](https://github.com/cisagov/ScubaGear/issues/1770)).

**app assignment + claims:** enterprise app owner (or app admin) assigns groups to app roles. group claim config is on the app: all security groups / all groups / groups assigned to the application / directory roles, plus optional filter. "Groups assigned to the application" is the recommended fix for overage, requires P1, and is *direct-member only* ("except when you're using the option to restrict the group claims to groups that are assigned to the application" — [group claims](https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/how-to-connect-fed-group-claims)). overage: entra drops the groups claim entirely and sends `_claim_names`/`_claim_sources`; apps that don't implement the graph fallback simply lose authz. teleport's bug is a nice illustration — users under the cap got sAMAccountName, users over it got object IDs, "every piece of RBAC keyed on names silently stops matching for the second set of users" ([teleport#69776](https://github.com/gravitational/teleport/issues/69776)). who decides: resource owner assigns the group; "Both the group owner and the resource owner manage group membership" — a weird shared-write but the exposure decision is the app owner's ([learn about groups](https://learn.microsoft.com/en-us/entra/fundamentals/concept-learn-about-groups)). microsoft's own advice is to stop sending groups and send app roles instead ([zero trust guidance](https://learn.microsoft.com/en-us/security/zero-trust/develop/configure-tokens-group-claims-app-roles)).

**SCIM:** scope = "Sync only assigned users and groups" (default) or all. "the Microsoft Entra user provisioning service can't read or provision users in nested groups… only… immediate members of an explicitly assigned group" ([how provisioning works](https://learn.microsoft.com/en-us/entra/identity/app-provisioning/how-provisioning-works)). dynamic groups are assignable but still not flattened. group *object* provisioning is a separate mapping toggle. workos's writeup of the three workarounds (flatten, assign children directly, reconcile via `transitiveMembers`) is the canonical practitioner rant ([workos](https://workos.com/blog/azure-entra-nested-groups-directory-sync)).

**populations:** B2B guests live in the workforce tenant as `userType=Guest`; consumers go in a separate "external" tenant (External ID; B2C discontinued for new customers may 2025). external tenants don't SSO to M365 and lack device/risk CA signals ([tenant configurations](https://learn.microsoft.com/en-us/entra/external-id/tenant-configurations)). so microsoft's answer is: partners in, customers out, two tenants.

**verdict:** right — real DAG groups with transitive graph APIs, owner concept on both groups and apps, app roles as the exposure vocabulary, entitlement-management catalogs as a two-sided grant. wrong — transitivity is inconsistent across consumers of the same graph (tokens yes, assignment/provisioning no, licensing no), overage is a footgun they document rather than fix, four group types, AUs that don't delegate the thing you want delegated, dynamic processing with 24h+ tails.

## 3. google workspace / cloud identity

**object model**

```
orgUnits(id, parent_id, path)                        -- tree, max depth 35, user in exactly ONE
users(id, orgUnitPath, ...)
groups(id, email, labels{discussion_forum|security|dynamic|locked}, dynamicGroupMetadata{cel_query}?)
memberships(group_id, member: user|group|serviceAccount, roles[{OWNER|MANAGER|MEMBER, expiry?}], restrictionEvaluations)
roleAssignments(role_id, assignedTo: user|group|SA, scopeType: CUSTOMER|ORG_UNIT, condition?)
app_access(app_id, scope: OU on/off/inherit | access_group on-only)
saml_app(attribute_mapping[], group_membership_mapping: groups[≤75] -> app_attribute)
```

**nesting:** full DAG via Cloud Identity Groups API. `searchTransitiveGroups`, `searchTransitiveMemberships`, `checkTransitiveMembership`, `getMembershipGraph` — but gated to Enterprise Standard/Plus and Cloud Identity Premium (403 otherwise) ([searchTransitiveGroups](https://docs.cloud.google.com/identity/docs/reference/rest/v1beta1/groups.memberships/searchTransitiveGroups)). the legacy Admin SDK directory scopes only return direct groups, which bites integrators (auth0 thread: customers "get confused when they don't have access due to missing a transitive group" — [auth0 community](https://community.auth0.com/t/support-transitive-group-membership-in-google-workspace/168498)). membership roles carry expiry (MEMBER only); nested-group expiry cascades as a default to children ([manage expirations](https://docs.cloud.google.com/identity/docs/how-to/manage-expirations)). nesting rules are type-based: security groups can only contain internal security groups, label is permanent ([security groups GA](https://workspaceupdates.googleblog.com/2021/08/security-groups-are-now-generally.html)); member restrictions must be at least as strict as the parent's; dynamic groups can't contain or be contained by other groups.

**OU vs group:** both, and the distinction is the source of most confusion. OU = where a user *lives* (one), carries baseline policy, inheritance down a tree, controls licensing and service on/off. groups = many, "access groups" can only turn a service *on* ("An access group can't turn off user access to a service that's turned on for an organizational unit" — [access groups](https://support.google.com/a/answer/9050643?hl=en)), "configuration groups" override settings. google's own doc: "a user's group settings always override their organizational unit's settings" but only for supported services. OUs control workspace settings, not GCP IAM. the practitioner consensus: don't mirror the org chart in OUs, use OUs for policy-different populations only ([patronum](https://www.patronum.io/organizational-units-vs-groups-google-workspace)).

**dynamic groups:** CEL queries over user attributes, 500/customer, premium SKUs only, no owners/managers, no nesting, must add security label to use for policy ([dynamic groups](https://docs.cloud.google.com/identity/docs/concepts/overview-dynamic-groups)).

**delegated admin:** the striking gap: Groups privileges "can't be limited to specific organizational units" ([privilege definitions](https://knowledge.workspace.google.com/admin/users/administrator-privilege-definitions)). user-management roles scope to OUs; groups roles scope to the whole customer, with 2024's Groups Editor/Reader roles adding a *condition* on the security label (all / security-only / non-security / exclude locked) — not arbitrary group sets ([GA announcement](https://workspaceupdates.googleblog.com/2024/12/provision-groups-admin-role-for-specific-group-types-general-availability.html)). per-group delegation is done with OWNER/MANAGER membership roles, which is actually elegant: delegation *is* a membership with a role. locked groups restrict even owners so IdP-synced groups don't drift ([locked groups](https://support.google.com/a/answer/15634160?hl=en)).

**app assignment + claims:** SAML app on/off is by OU (inherit/override) plus access groups (on-only). the SAML "group membership mapping" (may 2022) lets a super admin pick up to 75 named groups per app; the assertion includes those the user is in "directly or indirectly" — and only the *configured* parent name is sent even if membership came through a child ([group membership mapping](https://support.google.com/a/answer/11143403?hl=en)). renaming a group silently breaks the mapping. decided by: super admin on the app config. group owners have no say.

**SCIM:** outbound autoprovisioning for a catalog of apps, scoped by OU-enablement ∩ provisioning groups; "users from a secondary domain or from outside of your organization… are not provisioned"; no group object provisioning ("SCIM automatic synchronization from Google Workspace is currently limited to user provisioning" — [aws](https://docs.aws.amazon.com/singlesignon/latest/userguide/gs-gwp.html)), hence `ssosync`. inbound SCIM only arrived july 2026 ([workspace updates](https://workspaceupdates.googleblog.com/2026/07/streamline-identity-lifecycle-management-in-Google-Workspace-with-new-inbound-SCIM-support.html)).

**populations:** one namespace per domain, which is the problem: consumer accounts on your domain become "unmanaged users" the moment you verify it; conflicting accounts need the transfer tool, CSV invites, or forced `%@gtempaccount.com` renames ([transfer tool](https://support.google.com/a/answer/6178640?hl=en)). groups *can* contain external members (gated by settings; tightening in Q2 2026). so google has one directory that leaks into consumer identity and vice versa, and a decade of tooling to mop it up.

**verdict:** right — membership-with-roles-and-expiry is the best membership primitive of the bunch; transitive APIs are first-class; type-labels (security/locked) constrain nesting sanely; access-on-only groups layered on OU-policy is defensible. wrong — OU+group duality confuses everyone; groups admin can't be OU-scoped; transitive APIs paywalled; 75-group SAML mapping by name; the consumer/workforce namespace collision.

## 4. jumpcloud

**object model** — everything is a "bind" in a graph:

```
users ; user_groups(static|dynamic{attribute rules, exemptions})
devices ; device_groups(static|dynamic) ; policies ; policy_groups
applications ; radius_servers ; directories(ldap|o365|gworkspace|ad)
binds(src, dst)  -- user→user_group, user_group→application|radius|directory|device_group, device_group→policy_group...
admins(role: one of ~9 built-in or ≤20 custom; org-wide)
```

([glossary](https://jumpcloud.com/glossary), [connect users to resources](https://jumpcloud.com/support/connect-new-users-to-resources), [v2 api "JumpCloud Graph"](https://github.com/JoBrad/jcapi-go/blob/main/v2/README.md)). "All resources in JumpCloud are implicitly denied" until bound.

**nesting:** none, on principle. their blog is the clearest anti-nesting argument among vendors: "members of child groups inherit the entitlements of their parent group(s)… can result in unintended entitlements, entitlement conflicts, and troubleshooting challenges"; replacement is ABAC via dynamic groups ([nested groups](https://jumpcloud.com/blog/nested-groups)). **OU:** none. **dynamic:** attribute rules on the object's own attributes only; device groups can't key off bound users' groups ([community](https://community.jumpcloud.com/t5/jumpcloud-product-discussions/dynamic-groups-automation-using-the-api/m-p/3411)); "review before apply" mode is a nice touch.

**delegated admin:** weak. roles are function-scoped and org-wide; "An Admin can have only one role assigned"; 20 custom roles; no group- or OU-scoped delegation ([custom admin roles](https://jumpcloud.com/support/custom-admin-roles), [admin portal roles](https://jumpcloud.com/support/admin-portal-roles)).

**app assignment + claims + SCIM:** this is the interesting one. the app's User Groups tab is the only input: SAML "include group attribute" sends exactly "groups that connect the user to the application" ([SAML attribute notes](https://jumpcloud.com/support/saml-attribute-notes)), and SCIM "Enable management of User Groups and Group membership" pushes exactly those same bound groups ([aws jumpcloud guide](https://docs.aws.amazon.com/singlesignon/latest/userguide/jumpcloud-idp.html)). assignment, claim, and provisioning scope are one edge. the bind is editable from either end (group → applications tab, or app → user groups tab) but the permission is global admin either way.

**populations:** workforce only; no CIAM story. **verdict:** right — one edge drives access, claims, and SCIM; flat + ABAC is honest about what nesting costs. wrong — no delegation to speak of; flat forces rule duplication at scale; dynamic rules can't see relationships.

## 5. onelogin

**object model**

```
users(group_id?, ...)                 -- a user is in AT MOST ONE group
groups(id, security_policy_id?)       -- "think of them as departments"
roles(id, apps[], users[], admins[])  -- many-to-many; the actual access unit
mappings(condition_expr over user attrs|memberOf|group, actions: set_group|add_role|set_attr)  -- tenant-wide
app_rules(app_id, condition, action: set_param|set_groups_in_app)                        -- per app
privileges(effect, action, scope: users|apps|roles/{id}|groups/{id})  -- delegated admin add-on
```

"Users may only belong to one group at a time" ([groups KB](https://onelogin.service-now.com/kb_view_customer.do?sysparm_article=KB0010616)); roles are "simply a collection of apps" and multi-role landed as a feature ([multiple roles](https://www.onelogin.com/blog/multiple-roles-per-user)). so onelogin's "group" is effectively an OU with a policy pointer, and "role" is what everyone else calls a group. no nesting of either; no dynamic groups per se — mappings are the rule engine that *writes* group/role membership from attributes. delegated admin: built-in "Manage group" / "Manage role" privileges, plus custom privileges scoped to `roles/{id}` ([privileges](https://support.onelogin.com/kb/4267043/privileges)). claims: a per-app parameter `User Roles` macro or a memberOf passthrough, multi-value flag. SCIM: "OneLogin doesn't have the concept of groups like other third-party SCIM providers. It only has roles" — app rules map "for each role matching X → set groups in app" ([workos onelogin scim](https://workos.com/docs/integrations/onelogin-scim)). populations: workforce only. **verdict:** the one-group-per-user design is the OU idea done without a tree; roles-as-app-bundles is clean for small shops but the three overlapping rule systems (mappings, app rules, privileges) are a tell that the core model was too thin.

## 6. rippling (brief)

HR record is the directory; "Supergroups" are dynamic groups over any employee attribute via RQL, with "access assignments" tying a supergroup to an app integration (and to per-app roles/licenses); no static-group-centric model, no nesting ([supergroups](https://www.rippling.com/products/it/identity-access-management), [serval scopes](https://docs.serval.com/sections/integrations/rippling)). delegated admin is attribute-scoped permission profiles with include/except sets ([permissions](https://www.rippling.com/products/it/platform/permissions)) — probably the best delegation UX, because scope is a query, not a list. complaints are pricing/support, not model ([techradar](https://www.techradar.com/pro/rippling-it-iam-solution-review)). lesson: when the IdP *is* the HRIS, "groups" collapse into saved queries.

## 7. aws iam identity center (brief)

```
users ; groups ; group_memberships(user)         -- flat; "Nested groups aren't supported"
permission_sets ; account_assignments(principal: user|group, account, permission_set)
applications ; application_assignments(principal, app)
```

identity store is a SCIM-fed mirror; SCIM subset only (eq filter, no PATCH remove-all, no multi-valued attrs; 20–40 min sync cadence) ([scim limitations](https://docs.aws.amazon.com/singlesignon/latest/developerguide/limitations.html)). nested users "might receive a 'You do not have any applications' message" ([assign app access](https://docs.aws.amazon.com/singlesignon/latest/userguide/assignuserstoapp.html)); AD sync *does* flatten, so behavior differs by source. delegation is IAM-policy-on-ARNs with tags, plus delegated-admin member account ([delegating permission sets](https://aws.amazon.com/blogs/security/delegating-permission-set-management-and-account-assignment-in-aws-iam-identity-center/)). trusted identity propagation authorizes downstream services on group membership — flat groups, direct members only.

## 8. practitioner complaint digest (model-level, not UI)

- **nesting is inconsistently honored.** entra is the poster child (tokens transitive, assignment/provisioning/licensing not); AD→okta flattens; entra→SCIM doesn't; AD→aws flattens, entra→aws doesn't. every downstream tool has a doc page about it ([atlassian](https://support.atlassian.com/provisioning-users/docs/how-does-azure-ad-for-nested-groups-work/), [workos](https://workos.com/blog/azure-entra-nested-groups-directory-sync)).
- **token bloat.** kerberos PAC: ~1,015 group hard cap, 12,000-byte default MaxTokenSize, recursive evaluation means nesting makes it worse not better ([woshub](https://woshub.com/kerberos-token-size-and-issues-of-its-growth/), [ms archive](https://learn.microsoft.com/es-es/archive/blogs/shanecothran/maxtokensize-and-kerberos-token-bloat)). cloud equivalents: okta 100/claim, entra 150/200 then nothing, google 75 configured names.
- **sprawl from forced duplication.** okta's assignment≠push rule and name-regex claims mean three groups per team; gitlab's six-category taxonomy exists because the model doesn't carry the semantics ([gitlab nomenclature](https://handbook.gitlab.com/handbook/security/corporate/systems/okta/group/nomenclature)).
- **dynamic group latency.** entra's 24h+ and "pause all groups" ([office365itpros](https://office365itpros.com/2023/11/23/pause-membership-processing-2/)); google warns external-IdP dynamic groups "can introduce a delay for policy updates."
- **delegation scoped to the wrong thing.** entra AUs delegate group properties not members; google groups admin can't be OU-scoped; okta group owners have no rights; jumpcloud has no scope at all.
- **name-keyed exposure is brittle.** google requires re-entering renamed groups; okta regex filters break on rename; entra overage flips names to object IDs mid-fleet.

## cross-product comparison

| | okta | entra | google | jumpcloud | onelogin | rippling | aws idc |
|---|---|---|---|---|---|---|---|
| groups nest | no | yes (security only; DAG) | yes (DAG, type-constrained) | no | no | no | no |
| transitive API | n/a | memberOf/transitiveMemberOf/check | search/checkTransitive (premium) | n/a | n/a | n/a | n/a |
| nesting honored for app assign/SCIM | n/a | **no** | partial (SAML yes, SCIM n/a) | n/a | n/a | n/a | no |
| OU-like | realms (users only) | admin units (admin only) | OUs (tree, policy, 1 per user) | none | "group" (1 per user) | none | none |
| dynamic | group rules (no chaining) | rules, slow, memberOf dying | CEL, 500, premium | attr rules + review | mappings | supergroups/RQL | none |
| delegation primitive | resource sets | AU + owners + EM catalogs | OU scope + member roles + label conditions | global roles | privileges on roles/{id} | attribute-scoped profiles | IAM policy on ARNs |
| who decides app exposure | app admin (regex on names) | app owner (assign group→app role) | super admin (OU/access group + 75 names) | global admin (bind) | admin (role↔app) | admin (access assignment) | admin (assignment) |
| claim cap | 100/claim | 150 saml / 200 jwt → overage | 75 configured | bound groups | n/a | n/a | n/a |
| SCIM scope = app assignment | users yes; groups separate push | yes (direct members only) | OU ∩ groups, users only | yes, same bound groups | roles→groups via rules | supergroup assignment | n/a (inbound) |
| ext/B2C population | separate product (CIC) | guests in tenant; consumers in external tenant | same namespace (conflicts) | none | none | none | none |

## lessons for our draft model

**where we match the best of them**

- one `groups` table with a DAG `memberships(member: person|group)` is entra/google's shape, minus their type zoo. keep it one edge type; google's membership roles + expiry are worth stealing (`memberships.role`, `memberships.expires_at`) because it makes "owner/manager" *a membership* rather than a parallel admin system — that's the cleanest delegation primitive anyone shipped.
- materialized `effective_memberships` is the right call, and it should be the **only** thing any consumer reads — claims, SCIM scope, grants evaluation, all of it. entra's whole class of "nested works for tokens but not provisioning" bugs comes from different subsystems walking the graph differently. we have one table; never let a second path exist. (also: compute it synchronously or near-synchronously. entra's 24h dynamic tail is what "eventually consistent membership" feels like to users.)
- `grants(grantee_group, permission, target_group, recursive?)` is okta's resource-set model expressed relationally, and better than entra AUs because it delegates *membership*, not object properties. two things to add from the field: (1) okta's "groups that confer admin can't be managed by delegated admins" rule exists for a reason — a grant on a group that is itself a grantee is a privilege-escalation path; check for it. (2) rippling's include/except shows that negative scope is wanted in practice.
- `app_groups(app, group, claim_name, required?)` as the single edge that drives assignment, claim emission, and SCIM scope is exactly jumpcloud's bind and it's the thing okta (assign/push/regex) and entra (assignment/claim-config/provisioning-scope as three settings) get wrong. `claim_name` per edge also kills the name-keyed brittleness — the app never sees our group names unless we choose to.

**where we diverge, and whether that's good**

- **"exposure is a permissioned act by the group's manager."** nobody does this. in every product the *app side* decides which groups it consumes: okta app admin, entra enterprise-app owner, google super admin, jumpcloud global admin. the closest analogs are entra's entitlement-management catalogs (resource owners contribute groups into a catalog; package managers compose from it — a two-sided grant, but still admin-driven) and entra's "both the group owner and the resource owner manage group membership" shared-write (which is a symptom, not a design). so our model is novel here. i think it's right for a 150-person directory — it makes "who can learn X is in Y" an authz question with an owner — but be aware of the inversion cost: onboarding a new app requires N group managers to act, not one app admin. you probably want a grant permission like `expose_to_apps` so a directory admin can hold it on a root group with `recursive=true` and do the bulk work, while team managers hold it on their own subtree.
- **no OU.** correct. google's OU/group split is the single most confusing thing in this survey, and okta's realms and entra's AUs are both "we needed an admin-scoping container and didn't want it to be a group." our DAG + recursive grants *is* the OU: a grant on a parent with `recursive=true` is OU-scoped delegation without a second hierarchy. don't add one.
- **no dynamic groups in the draft.** fine for 150 people. if you add them later, do it as a rule that *writes* memberships (okta/onelogin style) rather than a group whose membership is computed at read time (entra style) — then `effective_memberships` stays the only truth and you don't inherit the "dynamic groups can't be owned/nested/added to AUs" exception list from google and entra.
- **SCIM = effective membership of groups attached to the app.** good, and it's what jumpcloud does. two field lessons: push *group objects* only for app_groups edges (never the whole transitive closure — downstream apps choke on child-group references, which is literally the entra→SCIM bug), and make the group sync idempotent-PATCH rather than okta's "Push Now" full overwrite. also decide what happens to a target group's membership when a user is *disabled* but still nominally a member (okta's lingering-deactivated-users bug).
- **two populations, 150 in / 50k out.** every vendor that tried one directory for both regretted it (google's unmanaged/conflicting accounts; entra's guest-in-tenant B2B model that then needed a separate external tenant anyway). okta and microsoft both ended at "two tenants." the 50k community users should not be rows in `memberships` and shouldn't be reachable by `grants` or `app_groups` at all — keep them in a different table/service with their own authn, and if an app needs both, it federates to two issuers. the one thing to decide early: can a community user ever be *promoted* into the directory (contributor → staff)? google's transfer tool is what that looks like when you didn't plan for it.
- **claim size.** with a 150-person directory you won't hit 100/150/200, but the *design* lesson stands: because exposure is per-edge, a token for app A only ever contains app A's claim names. you've structurally eliminated overage. keep it that way — don't add an "all groups" claim option, even as a convenience.

**one thing to add that the draft doesn't mention:** a `disable_nesting`/type constraint. google's security-label rule ("a security group may only contain security groups") and entra's new `disableNesting` both exist because someone nested a loosely-managed group under a sensitive one. with a single edge type, the cheap version is a per-group flag `accepts_group_members` (or a rule that a group with outstanding grants/app_groups can't gain a child whose manager differs from its own without approval). cycle prevention you already have; this is the *semantic* cycle check.
