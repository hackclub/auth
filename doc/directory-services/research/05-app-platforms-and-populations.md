# app-platform group models & the two-population split

> raw research report, 2026-10-20. one of five inputs to `../README.md`.

## part A — how app platforms model groups, and what broke

### 1. github

**object model.** enterprise → organizations → teams (nestable, one parent per child, many children per parent) → members. repository grants (read/triage/write/maintain/admin) attach to teams or individuals. teams can only contain org members. ([about teams](https://docs.github.com/en/organizations/organizing-members-into-teams/about-teams))

**nesting: yes, since june 2017.** before that, teams were flat and big orgs drowned: kubernetes opened an issue the same day the feature shipped because they had "244 teams and still going strong" and their teams page was unnavigable ([kubernetes/community#720](https://github.com/kubernetes/community/issues/720)). the announcement: "child teams inherit their parent's access permissions, so repository permissions and @mentioning among nested teams work from top to bottom" ([github blog](https://blog.github.com/2017-06-13-nested-teams-add-depth-to-your-team-structure/)).

**direction, carefully.** a grant to the parent applies to everyone in the subtree. membership does *not* flow either way automatically — "members of a child team are not direct members of the parent team," and parent members are not members of children ([about teams](https://docs.github.com/en/organizations/organizing-members-into-teams/about-teams)). in DAG terms: child team is a member-of parent team; parent's grants cover child's members. the HN thread on launch day complained the parent/child naming was confusing and "super/sub" would have been clearer ([hn](https://news.ycombinator.com/item?id=14546960)) — a naming warning for our `memberships` table. secret teams cannot be nested at all, and via the API "the privacy for parent teams cannot be secret" ([changing team visibility](https://docs.github.com/en/enterprise-cloud@latest/organizations/organizing-members-into-teams/changing-team-visibility), [teams REST](https://docs.github.com/en/rest/teams/teams)).

**where nesting leaks.** jamie tanna's 2024 post: nesting "is almost never actually what you want" for authz — CODEOWNERS and review-requests require each *individual* child team to be added as a collaborator with write access; inherited access doesn't count ([jvt.me](https://www.jvt.me/posts/2024/09/12/github-authz-teams/)). i.e. github's own features bypass the hierarchy and consult direct grants.

**team sync / EMU.** classic team sync: entra *security* groups only, "nested group memberships and microsoft 365 groups are not supported," up to 5 IdP groups per team, no IdP groups >5000 members. EMU: "teams connected to IdP groups cannot be parents of other teams nor a child of another team" ([docs](https://docs.github.com/en/enterprise-cloud@latest/admin/managing-iam/provisioning-user-accounts-with-scim/managing-team-memberships-with-identity-provider-groups)) — though a docs issue reports it does actually work via an ordering bug ([github/docs#36078](https://github.com/github/docs/issues/36078)). large customers complain EMU "has no concept of allowing IdP-managed hierarchies — only planar teams" and there's a 1500-team-per-org cap ([discussion #126547](https://github.com/orgs/community/discussions/126547)). manual adds to synced teams are overwritten on the next reconcile.

**delegation.** team maintainers (per-team admin: membership, settings, repo grants), custom org roles, and an enterprise-level policy restricting who may invite outside collaborators to "enterprise admins only" ([changelog](https://github.blog/changelog/2022-04-08-enterprise-admin-only-policy-for-outside-collaborators/)).

**second population.** outside collaborators: repo-scoped, "not explicitly a member of the organization," cannot be on teams, and "people who are not members of the organization cannot view any teams" ([roles](https://docs.github.com/en/organizations/managing-peoples-access-to-your-organization-with-roles/roles-in-an-organization)). notably EMU *eliminates* this population: "a repository collaborator must be part of your enterprise, with a managed user account" ([collaborators REST](https://docs.github.com/en/rest/collaborators/collaborators)).

**verdict.** nesting bought navigability and top-down grants, but github never made the hierarchy authoritative — many features read direct edges only. the "not in directory" population is handled by making them invisible to the team graph entirely, which is exactly our invariant.

### 2. slack enterprise grid

**object model.** org → workspaces → channels. users are org-level. two *separate* group systems: **IDP groups** (created by SCIM, org-wide, map to workspace and channel membership, can be "required" for a workspace) and **user groups** (@handles; workspace-level on business+, org-level on grid when admin-created). slack's own docs: org-level user groups "can't be managed from SCIM provisioning or combined with IDP groups" ([create user groups](https://slack.com/help/articles/212906697-Create-and-edit-user-groups), [connect IdP groups](https://slack.com/help/articles/115001435788-Connect-identity-provider-groups-to-your-Enterprise-organization)). jumpcloud: "a Slack Enterprise Grid SCIM integration can only create and manage IdP Groups, not User Groups" ([jumpcloud](https://jumpcloud.com/support/integrate-with-slack)).

**SCIM quirks.** SCIM is org-wide — token must be from an org-level install; "creating SCIM groups will create an IDP group, which may or may not be the correct behavior" ([slack SCIM docs](https://docs.slack.dev/admins/scim-api/)). rate limits are shared across *all* SCIM apps in the org. users can't be deleted, only deactivated. single-channel guests can't be created via SCIM; multi-channel guests via SCIM only on grid.

**nesting: no.** delegation: fixed role set (org owner/admin, workspace owner/admin), no custom roles.

**second population.** guests (SCG/MCG) and slack connect. guests "can't be added to user groups ... and will not be able to mention user groups" ([user groups](https://slack.com/help/articles/212906697-Create-and-edit-user-groups)); guest MFA is enforced natively by slack, not your IdP; MIT's policy notes grid role restrictions force internal-domain people to be full members ([mit](https://libguides.mit.edu/c.php?g=176106&p=10087136)). guest sprawl: "slack doesn't warn you when you add a guest to a channel that contains sensitive information" ([thread-patrol](https://thread-patrol.com/blog/slack-guest-accounts-management)).

**verdict.** two overlapping group primitives with different owners (IdP vs admin) and no bridge is the documented mess. the `required` concept (IdP group → required workspace) exists and works; lift it.

### 3. atlassian cloud

**object model.** org → sites → products; flat groups; product access is "a group per product role" — "every Product Role needs a default group assigned... the system is just looking up the default group for Jira Users and adding the user into that group" ([resolution wiki](https://wiki.resolution.de/doc/atlassian-user-management/core-concepts/groups-access-control-in-atlassian-cloud), [default groups](https://support.atlassian.com/user-management/docs/default-groups-and-permissions/)).

**nesting: no, confirmed, "won't do."** [ID-167](https://jira.atlassian.com/browse/ID-167) closed. stated reason: nesting "is not supported by major cloud identity providers like Microsoft Azure AD and Okta, which account for the vast majority of their user provisioning API usage" ([ACCESS-654](https://jira.atlassian.com/browse/ACCESS-654)). if you push nested groups via SCIM: "users lose memberships in the parent groups... permission inheritance isn't respected," and logs say `groupId cannot be added under other groupId` ([migration docs](https://support.atlassian.com/migration/docs/prepare-nested-groups-for-cloud-migration/)). atlassian shipped a dedicated "Azure AD for nested groups" connector purely to flatten.

**default-groups mess.** users auto-dropped into default groups consume licenses; `administrators` forces a jira license; SCIM-synced groups are read-only and "cannot be set as default" so admins hand-add provisioned users to `jira-software-users` anyway ([community](https://community.atlassian.com/t5/Atlassian-Access-questions/Can-I-change-default-access-groups-to-synced-groups/qaq-p/1151634)). [ACCESS-1996](https://jira.atlassian.com/browse/ACCESS-1996): entra nested groups assigned to the SSO app are silently ignored → SSO fails.

**second population — this is the interesting one.** three account types: managed accounts, **external users** (real atlassian accounts on a non-company domain, in the org, subject to "external user security" policy), and **portal-only customers** — "not Atlassian accounts... only apply to Jira Service Management" ([global account model](https://support.atlassian.com/user-management/docs/make-atlassians-global-account-model-work-for-you/), [external user security](https://support.atlassian.com/security-and-access-policies/docs/what-is-external-user-security/)). portal-only accounts sit *outside* guard's auth policies and password policy, and need a *separate* SAML integration with JIT provisioning ([JSM customers SSO](https://support.atlassian.com/atlassian-cloud/kb/user-provisioning-and-saml-single-sign-on-for-jira-service-management-customers/)).

**verdict.** flat groups + "a group per product role" produces license surprises and a read-only-synced-group deadlock. but portal-only customers are the closest shipping analogue to our teenagers: accounts that can log in and raise tickets but are structurally a different type, invisible to the directory.

### 4. discord

**object model.** guild → roles (flat list) → members have a set of roles. role = `{position: int, permissions: bitfield string, managed, mentionable}`. member permissions = OR of all roles' bits, then per-channel overwrites in an 8-layer order (@everyone deny/allow → role deny/allow → member deny/allow); owner and ADMINISTRATOR short-circuit to ALL ([permissions docs](https://docs.discord.com/developers/topics/permissions), [docs PR #330](https://github.com/discord/discord-api-docs/pull/330/files)).

**hierarchy is only for actions on others.** "aside from specific hierarchy-gated actions, permissions do not obey the role hierarchy." manage roles: "can create and modify roles positioned below their own... limited to assigning only the permissions that they themselves possess" ([support](https://support.discord.com/hc/en-us/articles/214836687-Discord-Roles-and-Permissions)). overwrites ignore hierarchy entirely.

**what a total order buys you.** delegation falls out of one integer: "can i edit X" = `my_top > X.position`, plus "can't grant what you don't have." no cycles possible, no separate grants table, O(1) check, and no bootstrap problem (owner is above everything).

**where it falls over.** (a) one total order can't express two independent axes — a mod ladder and cosmetic/level roles share one list, so "position beats permission" surprises everyone. (b) hard cap of 250 roles, not raised for anyone; large RP servers and bot-generated roles hit it ([feature request](https://support.discord.com/hc/en-us/community/posts/360056091951-Increase-Role-Limit)). (c) bots invited later sit lower and "silently fail"; reordering is drag-one-at-a-time ([reorder request](https://support.discord.com/hc/en-us/community/posts/11090718981527-Improve-Reordering-Roles-Functionality)). (d) position collisions sort by id — unpredictable from the UI. (e) ADMINISTRATOR is a permission bit, not a position, so an admin can't edit a role above them.

**second population:** none — everyone is a guild member with @everyone. **verdict:** a fantastic delegation primitive for a *single* community, useless as a directory. steal the anti-escalation rule, not the structure.

### 5. google workspace groups

**object model.** one `Group` object is simultaneously a mailing list, collaborative inbox, drive-sharing principal, cloud IAM principal, and (optionally) a security group. per-group roles: owner (full, can delete), manager (same minus delete), member. access types public/team/announcement/restricted bundle who-can-join/post/view-members ([create a group](https://support.google.com/a/answer/9400082)).

**nesting: yes, with a published matrix.** google's own IAM best practices define four group *kinds* — organizational, collaboration, access, enforcement — and a nesting matrix: organizational groups can be nested into anything; collaboration groups into nothing else; "don't nest access groups" ([groups best practices](https://docs.cloud.google.com/iam/docs/groups-best-practices)). **dynamic groups** can't nest in either direction and "cannot have managers or owners" ([dynamic groups](https://knowledge.workspace.google.com/admin/groups/manage-membership-automatically-with-dynamic-groups)). **security groups**: an irreversible label; "only a security group in the same organization can join another security group," applies even to super admins ([security groups](https://knowledge.workspace.google.com/admin/groups/control-access-to-sensitive-data-with-security-groups)). transitive-membership APIs (`searchTransitiveMemberships`, `getMembershipGraph`) exist but are enterprise-SKU-only and fail with 403 if you can't read *every* nested group ([querying memberships](https://docs.cloud.google.com/identity/docs/how-to/query-memberships)).

**the overloading problem.** latacora's "gripes with google groups": "if you're a GCP user... you probably know Google Groups as an access control mechanism. The bad news is we're both right" — self-service join settings on a group someone also gates authz on, and out-of-domain-posting confused with out-of-domain-membership ([latacora](https://www.latacora.com/blog/2018/05/29/gripes-with-google-groups/)). google's 2020 security-groups launch admitted admins had been using "naming conventions" as the workaround ([blog](https://workspaceupdates.googleblog.com/2020/09/security-groups-beta.html)).

**third-party read access.** groups API has admin / non-admin / namespace authorization modes; non-admins see groups "based on the domain settings, group's settings and... their membership roles" ([cloud identity auth](https://docs.cloud.google.com/identity/docs/concepts/auth)).

**verdict.** the richest model on the list, and the one with the most published "don't do this" guidance because one object serves five purposes. if our groups will also back mailing lists / LDAP, we need a kind/label and a nesting matrix on day one.

### 6. kubernetes rbac

no user or group objects. `Group` is an opaque string in a (Cluster)RoleBinding subject; the API server string-matches against the token's `--oidc-groups-claim`, which "must be an array of strings" ([authn](https://kubernetes.io/docs/reference/access-authn-authz/authentication/), [rbac](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)). composition lives on the *role* side: aggregated ClusterRoles union rules via label selectors ([KEP 502](https://github.com/kubernetes/enhancements/issues/502)). practical wounds: entra emits objectIDs and caps at 200 groups; forgetting `--oidc-groups-prefix` makes bindings silently no-op. **lesson:** the consumer stays flat and dumb; all nesting is the IdP's problem; compose permissions, not subjects.

### 7. aws iam / identity center

"user groups can't be nested; they can contain only users"; a user is in ≤10 groups; groups aren't principals ("groups relate to permissions, not authentication") ([iam groups](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_groups.html)). identity center: "doesn't support nested groups" and nested users get "You do not have any applications" at sign-in ([identity center](https://docs.aws.amazon.com/singlesignon/latest/userguide/users-groups-provisioning.html), [assign app access](https://docs.aws.amazon.com/singlesignon/latest/userguide/assignuserstoapp.html)); AD connector: "members of the parent group have console access, but members of child groups do not" ([directory service](https://docs.aws.amazon.com//directoryservice/latest/admin-guide/assign_role.html)). **does anyone miss it?** not loudly — the ecosystem routed around it: groups become thin "may assume these roles" containers and composition happens via roles/permission sets ([truss module](https://github.com/trussworks/terraform-aws-iam-user-group), [permission sets](https://docs.aws.amazon.com/singlesignon/latest/userguide/permissionsetsconcept.html)).

### 8. unix / posix

primary gid + supplementary list. NGROUPS_MAX was 32 before linux 2.6.4, 65536 since ([getgroups(2)](https://man7.org/linux/man-pages/man2/getgroups.2.html)); solaris defaults to 16; NFS AUTH_SYS truncates at 16 — "which can also mean people who should *not* be able to access files *can*" ([ngroups overview](https://www.j3e.de/ngroups.html)). sssd flattens AD nesting by reading the computed `tokenGroups` attribute — microsoft warns it's "an expensive operation on the domain controllers" ([tokenGroups](https://learn.microsoft.com/el-gr/windows/win32/adschema/a-tokengroups)). the real pain is transitive resolution cost: `id` is slow because resolving each gid pulls whole group member lists, and the libldb `memberof` plugin dominates CPU ([jhrozek](https://jhrozek.wordpress.com/2014/01/27/why-is-id-so-slow-with-sssd/), [rh tuning](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/tuning_performance_in_identity_management/assembly_tuning-sssd-performance-for-large-idm-ad-trust-deployments_tuning-performance-in-idm)). `ldap_access_filter` doesn't follow nesting at all — "prohibitively difficult" ([sssd#3046](https://github.com/SSSD/sssd/issues/3046)). **lesson:** every consumer ends up wanting a precomputed flat list; the directory should serve one.

### 9. linear / notion / figma / vercel

- **linear**: pushed SCIM groups "map 1:1 with teams"; name-based mapping to existing teams; deleting the SCIM group empties the team and makes it private ([linear scim](https://linear.app/docs/scim)).
- **notion**: SCIM groups → workspace groups; google's SCIM connector can't do groups at all ([notion](https://www.notion.com/help/provision-users-and-groups-with-scim)).
- **figma**: SCIM groups drive workspace/billing group and seat type; entra needs a *custom* app for groups ([figma](https://help.figma.com/hc/en-us/articles/37835780984215-Manage-SCIM-Groups-for-Microsoft-Entra-ID)).
- **vercel**: SCIM (via workos) maps groups → roles + access groups; "overwrites existing team permissions, creating potential lockout" ([vercel access groups](https://vercel.com/changelog/access-groups-now-generally-available-on-enterprise-plans), [howtoharden](https://howtoharden.com/guides/vercel/)).
- none nest. the protocol allows it — RFC 7643 §4.2: `members[].$ref` may be a Group, "the intention of the 'Group' type is to allow the service provider to support nested groups," with `direct`/`indirect` membership types ([rfc 7643](https://datatracker.ietf.org/doc/html/rfc7643)) — but entra won't expand nested groups over SCIM and okta flattens on import ([workos](https://workos.com/blog/azure-entra-nested-groups-directory-sync), [okta](https://support.okta.com/help/s/article/How-does-Okta-handle-nested-groups)). okta itself: "Okta doesn't support nested groups"; group rules are the substitute.

### part A comparison

| platform | nesting | direction | delegation | second population | documented wound |
|---|---|---|---|---|---|
| github | yes (tree, 1 parent) | grants flow parent→subtree; membership doesn't flow | team maintainers, custom org roles | outside collaborators: repo-scoped, can't see teams | CODEOWNERS/reviews ignore inheritance; IdP-synced teams can't nest; 1500-team cap |
| slack grid | no | — | fixed roles | SCG/MCG guests; excluded from user groups | IDP groups vs user groups, two systems no bridge |
| atlassian | no ("won't do") | — | org admin / user access admin | external users (in dir) vs portal-only (not accounts) | default-group licensing; synced groups can't be default |
| discord | no (total order) | position gates who-edits-whom | "below you, only perms you have" | none | 250 cap; one axis; overwrites ignore hierarchy |
| google groups | yes (DAG, typed matrix) | member-of; transitive APIs enterprise-only | owner/manager/member per group | external members infect parent as "external" | one object = email + authz; security label irreversible |
| k8s | no (strings) | — | role aggregation | n/a | 200-group entra cap; prefix foot-guns |
| aws iam/idc | no | — | n/a; roles instead | n/a | nested users "no applications"; ≤10 groups/user |
| posix/sssd | consumer flat; AD nested | tokenGroups flattens | n/a | n/a | NFS 16; slow `id`; access filter ignores nesting |
| linear/notion/figma/vercel | no | — | per-product | n/a | IdP-side nesting silently dropped |

## part B — the two-population split

### 10. microsoft entra

three models: **entra ID** (workforce tenant), **B2B guests** (same tenant, `userType=Guest`, `#EXT#` UPN), **external ID external tenant** (CIAM, "distinct and separate from your workforce tenant," no SSO to M365) ([overview](https://learn.microsoft.com/en-us/entra/external-id/external-identities-overview), [tenant configurations](https://learn.microsoft.com/en-us/entra/external-id/tenant-configurations)). microsoft also documents a fourth: a second *workforce* tenant as a partner boundary with cross-tenant sync ([deployment architectures](https://docs.azure.cn/en-us/entra/architecture/external-identity-deployment-architectures)).

**why guests-in-the-directory hurts** — these are exactly the failure modes we want to design out:
- they're first-class user objects; the only discriminator is one attribute. dynamic rule `user.objectId -ne null` includes guests; you must remember `-and (user.userType -eq "Member")`.
- "a guest user addition error in one group will block the updates of the same and other groups in the same tenant" ([troubleshoot dynamic groups](https://github.com/MicrosoftDocs/SupportArticles-docs/blob/main/support/entra/entra-id/dir-dmns-obj/troubleshoot-dynamic-groups.md)).
- attribute-based dynamic rules are gameable: attacker crafts a user in *their* tenant with matching attributes, gets invited, lands in the group ([tenable](https://www.tenable.com/indicators/ioe/entra/DYNAMIC-GROUP-FEATURING-AN-EXPLOITABLE-RULE)).
- default "limited" guest access still lets guests "search for groups by display name or object ID" and "read... membership and ownership" of non-hidden groups ([restrict guest permissions](https://learn.microsoft.com/en-us/entra/identity/users/users-restrict-guest-permissions)); trustedsec chained known objectIDs to dump users and groups, and microsoft called it "not technically a bug" ([unwelcome guest](https://trustedsec.com/blog/unwelcome-guest-abusing-azure-guest-access-to-dump-users-groups-and-more)).
- group claims: 150 SAML / 200 JWT, *all-or-nothing* — over the cap the claim vanishes and an overage pointer appears; mitigation is "groups assigned to the application" or app roles ([group claims](https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/how-to-connect-fed-group-claims)). "assignment required" → AADSTS50105, and "nested groups are not supported" for assignment; global admins bypass the check ([AADSTS50105](https://learn.microsoft.com/en-us/troubleshoot/entra/entra-id/app-integration/error-code-aadsts50105-user-not-assigned-role)).

### 11. okta

workforce identity cloud and customer identity cloud (auth0) are separate products with separate dashboards, APIs, SDKs, billing. mckinnon on why buy rather than extend: auth0 had "a service that is flexible and API-driven and great tools for developers... And you can't do that later, you have to start from the beginning" ([techcrunch 2022](https://techcrunch.com/2022/11/10/okta-ceo-opens-up-about-auth0-acquisition-saas-slump-and-lapsus-attack/)); okta had already tried with stormpath and the pre-auth0 "okta customer identity" (API access management as a paid add-on, admin-oriented DX). forrester framed it as a different buyer — app teams, not IT ([forrester](https://www.forrester.com/blogs/okta-acquires-identity-orchestration-and-ciam-vendor-auth0-for-6-5b/)). **auth0 organizations**: one user, many memberships, org-scoped roles, per-org connections, JIT membership; org roles aren't in tokens without an action ([organizations](https://auth0.com/docs/manage-users/organizations/organizations-overview)). okta WIC groups are flat and claims are capped at 100 groups per claim; the per-app groups-claim filter only applies to the org authorization server ([groups claim](https://developer.okta.com/docs/guides/customize-tokens-groups-claim/main/)).

### 12. keycloak

realms are the isolation unit: separate users, credentials, sessions, clients, issuers. a maintainer on why no cross-realm SSO: "There is no reason, it's just a design decision... Realms are isolated from each other" ([forum](https://forum.keycloak.org/t/cross-realm-single-sign-on/6134)). the maintainers' own organizations proposal: "modelling a customer as a realm is far from ideal... everything has to be re-created in each individual realm... applications essentially integrate with a different IdP for each customer" ([discussion #19054](https://github.com/keycloak/keycloak/discussions/19054)). workaround is identity brokering realm-into-realm (one-directional, shadow accounts) or preview token exchange. organizations (kc 25/26) put tenants in one realm, but "organization groups cannot be used in Keycloak authorization policies" ([server admin](https://www.keycloak.org/docs/latest/server_admin/index.html), [phasetwo](https://phasetwo.io/blog/multi-tenancy-options-keycloak/)). **lesson:** hard isolation at the account layer makes *staff who also need community access* painful — exactly the case we'd hit if we used two systems.

### 13. aws cognito vs identity center

fully separate. aws FAQ: "Amazon Cognito is a service that helps you manage identities for your customer facing applications; it is not a supported identity source in IAM Identity Center" ([faq](https://aws.amazon.com/iam/identity-center/faqs/)). no bridge, by design.

### 14. google

consumer accounts, workspace/cloud identity managed accounts, and visitors. consumer accounts on your domain become "unmanaged" and then "conflicting" when you provision the same address; resolution is transfer or eviction, renaming the consumer account to `user%domain@gtempaccount.com` ([evict consumer accounts](https://docs.cloud.google.com/architecture/identity/evicting-consumer-accounts), [unmanaged users](https://knowledge.workspace.google.com/admin/users/find-and-add-unmanaged-users)). cloud identity free gives 50 managed-but-unlicensed accounts. **visitor sharing**: PIN-verified non-google identities, 7-day sessions, "can't be added as members of the shared drive," not supported on cloud identity editions ([visitor sharing](https://knowledge.workspace.google.com/admin/drive/allow-sharing-to-non-google-users-with-visitor-sharing)) — a population that can touch resources but never enters the directory.

### 15. practitioner writing: one table, two systems, or one account table + separate directory graph?

- **identity-industry consensus: two systems.** "customer identities have sessions, workforce identities have lifecycles"; "never mix them: run separate platforms, separate data stores, separate policies" ([digitalidentitybook](https://digitalidentitybook.com/blog/ciam-vs-workforce-iam-key-differences), [startwithidentity](https://startwithidentity.com/articles/ciam-vs-iam/)). the vendors agree with their product lines (entra/external ID, okta/auth0, cognito/IDC).
- **schema-level: one thin identity table + separate profile/membership tables.** the "god table" with a role column is widely discouraged, but three login routes is an overcorrection ([dev.to](https://dev.to/kolardev/designing-a-user-model-for-multiple-roles-without-losing-your-mind-4boh)); devise's wiki documents both `Admin` model and `admin:boolean` ([devise wiki](https://github.com/heartcombo/devise/wiki/How-To:-Add-an-Admin-role)).
- **the pattern you drew has a name-ish.** "separating organization membership from user accounts... the account becomes the durable subject and the membership becomes the changeable authorization object" ([nhimg](https://nhimg.org/faq/why-does-separating-organization-membership-from-user-accounts-matter-for-access/)); oso's "don't bundle authn and authz" ([oso](https://www.osohq.com/post/dont-bundle-authn-and-authz-just-because-its-convenient)); and zanzibar, which models groups as relation tuples with group-in-group and notes evaluating membership "can entail following a long chain of nested group memberships" ([zanzibar paper](https://www.usenix.org/system/files/atc19-pang.pdf)). nobody has a crisp single term; the closest shipping products are atlassian's account/portal-only split and auth0 organizations (one account, N memberships). i'd call ours **"thin account, separate membership graph"** — accounts are the authn subject; the directory is a graph over a *subset* of accounts.

### 16. third-party oauth app risk

| platform | who approves app exposure | granularity | how org structure is shielded |
|---|---|---|---|
| google workspace | tenant admin (app access control: trusted/limited/blocked, per-scope since 2024) ([workspace updates](https://workspaceupdates.googleblog.com/2024/12/configure-third-party-apps-by-select-api-scopes-general-availability.html), [admin help](https://knowledge.workspace.google.com/admin/apps/control-which-third-party-and-internal-apps-access-google-workspace-data)) | per app, per scope | groups API non-admin mode honors per-group visibility settings; developer picks internal/external audience |
| slack | workspace owner / org admin via app approval; scope changes re-trigger ([managing app approvals](https://docs.slack.dev/admins/managing-app-approvals/)) | per app, scopes shown | `admin.*` scopes require org-level install by an org admin; `usergroups:read` is a normal scope |
| github | org owner approves each OAuth app per org; restrictions on by default ([oauth app restrictions](https://docs.github.com/en/organizations/managing-oauth-access-to-your-organizations-data/about-oauth-app-access-restrictions)) | per app, per org | visibility evaluated against the authorizing user; secret teams; non-members see no teams |
| entra | user consent (classified low-risk only) or admin consent workflow ([consent overview](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/user-admin-consent-overview)); "users can register applications" is on by default ([default permissions](https://learn.microsoft.com/en-us/entra/fundamentals/users-default-permissions)) | per app, per permission | `Directory.Read.All` is the big leak; mitigation is groups claim "assigned to the application" / app roles, which the *app's admin* configures |

the common shape: approval sits with the **tenant admin or resource owner**, never with the group's manager, and exposure is coarse (per app/scope) with the directory shape leaking through whatever the authorizing user can see. nobody ships "this group, to this app, under this name" as a first-class grant. entra's "groups assigned to the application" + app roles is the nearest — but it's configured on the app side by an app admin, and microsoft explicitly recommends app roles over groups so the app has "its own authorization vocabulary" instead of directory names ([app roles vs groups](https://learn.microsoft.com/en-us/security/zero-trust/develop/configure-tokens-group-claims-app-roles)). okta's per-app groups-claim allowlist is the other near miss.

### part B comparison

| product | one directory or two? | how externals are kept out of pickers/queries |
|---|---|---|
| entra B2B | one | they aren't — `userType` filter + guest access restrictions; default still allows group search by name |
| entra external ID | two (separate tenant) | separate directory entirely; no M365 SSO |
| okta WIC / auth0 | two products | separate stores; auth0 orgs = memberships on one account |
| keycloak realms | N directories | hard isolation; cross-realm via brokering shadow accounts |
| cognito / IDC | two | not connectable |
| google | managed vs consumer vs visitor | consumer accounts evicted from domain; visitors are PIN sessions, not directory objects |
| atlassian | one account system, two account *types* | portal-only customers aren't atlassian accounts; outside guard, separate SAML |
| our draft | one account table, one directory graph over a subset | structural: community accounts have no directory rows |

## lessons for the draft model

1. **everyone flattens; materialize and serve flat.** k8s, aws, atlassian, okta, posix/sssd, and every SaaS SCIM target consume flat lists. `effective_memberships` is the product; `memberships` is the editing surface. serve `effective_memberships` via SCIM `groups` with `type: indirect` (RFC 7643 allows it) and via LDAP `memberOf` as transitive (what AD `tokenGroups` does and what sssd wants). never make a consumer walk the DAG.

2. **nail the direction in the schema name, not the docs.** github's parent/child naming confused people on day one, and "parent inherits child's permissions" vs "child inherits parent's grants" are the same fact read from opposite ends. consider `memberships(group_id, member_id)` with an explicit comment: "a group member's members are transitively members of `group_id`; grants to `group_id` cover them." that is github's semantics and google's organizational-group semantics.

3. **`app_groups` is the right primitive and the gap in every platform.** it gives you what entra's "groups assigned to the application" and okta's allowlist give, plus by construction it dodges the claim-overage cliff (entra 150/200 all-or-nothing, okta 100). `claim_name` decoupled from the directory name is exactly microsoft's app-roles argument: the app gets a stable vocabulary, not your org chart. keep it.

4. **but think about who approves.** every platform puts approval with the tenant admin or the resource owner (org owner on github), never the group manager alone. a group manager exposing a group to an arbitrary community-created app is the consent-phishing shape (entra). suggestion: two-sided — app owner *requests* a claim, group manager (or a directory admin, for sensitive groups) *approves* — mirroring github's app-approval request and slack's scope-change re-approval. also decide whether changing `claim_name` or `required` after the fact re-triggers approval.

5. **`required` has prior art and a known footgun.** entra "assignment required," okta app assignment, slack "required workspaces." entra's version doesn't follow nesting; yours does because you have `effective_memberships` — good. entra's other footgun: global admins silently bypass. decide explicitly whether directory admins bypass `required`, and log it either way.

6. **keep the invariant structural, not a WHERE clause.** entra B2B is the cautionary tale: same object type, one attribute, and every dynamic rule, picker, and enumeration path has to remember the filter. make directory tables FK to a `directory_persons` row (or persona) that community accounts simply don't have; then "appears in the directory" is a join, not a predicate someone forgets. atlassian's portal-only accounts and google visitors are the same idea in product form.

7. **delegation needs an anti-escalation rule, not just a grant.** discord's "only roles below you, only perms you have" and github's team-maintainer scope are both bounded. in a DAG, "manage group G" should imply descendants, never ancestors, and you need a cycle check on `memberships` plus a rule against a manager adding themselves to a child to inherit the parent's grants. your `grants(grantee, permission, target, recursive?)` already reproduces google's nesting matrix — document the matrix.

8. **if groups will also be mailing lists or LDAP posixGroups, type them now.** google needed an irreversible security label and a four-kind taxonomy to undo one-object-five-purposes; latacora's gripes are what happens otherwise. a `kind` on `groups` (access vs collaboration vs organizational) with a nesting matrix costs nothing today and is impossible to retrofit cleanly.

9. **SCIM and LDAP only ever see the directory population.** this falls out of (6), but state it: community accounts are not SCIM resources and not LDAP entries. slack and github both show what happens when a provisioning system and an in-product system disagree about who's "in."

10. **group visibility inside the directory, too.** github's secret teams and google's per-group "who can view members" exist because even staff shouldn't see everything. `app_groups` solves exposure to apps; consider a visibility bit for directory-internal pickers as well.

11. **transitive computation is the expensive part — you already chose right by materializing.** sssd's memberof plugin, google's enterprise-only transitive APIs, and zanzibar's long-chain problem all say the same thing. make `effective_memberships` invalidation incremental per edge change, and keep per-person effective group counts modest (consumers choke at 16 / 100 / 200).

12. **the one place two-systems beats you: staff who are also community members.** keycloak realms show the pain of a person existing twice. your single account table handles it — one login, optional directory persona — which is auth0 organizations' shape and the actual reason to prefer your pattern over entra-style separate tenants.
