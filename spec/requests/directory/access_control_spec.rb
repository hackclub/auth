# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Directory access control", type: :request do
  # ── helpers ──────────────────────────────────────────────────────
  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  def make_admin(identity)
    bu = Backend::User.find_by(identity: identity) || create(:backend_user, identity: identity)
    bu.update!(directory_services_admin: true)
    identity.reload # clear cached nil for backend_user association
    bu
  end

  def make_directory_person(identity)
    create(:directory_person, identity: identity)
  end

  def grant!(person, collection, permission)
    slug = "g-#{person.id}-#{collection.id}-#{permission.tr('_', '-')}"
    grantee = create(:directory_group, slug: slug)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: grantee, member_person: person, created_by_identity_id: person.identity_id)
      Directory::Grant.create!(grantee_group: grantee, target_collection: collection, permission: permission, created_by_identity_id: person.identity_id)
    end
    grantee
  end

  # ── shared state ────────────────────────────────────────────────
  let(:community_identity) { create(:identity) }
  let(:staff_identity)     { create(:identity) }
  let(:admin_identity)     { create(:identity) }

  let(:group)       { create(:directory_group, slug: "engineers", name: "Engineers") }
  let(:entitlement) { create(:directory_entitlement, slug: "docs-access", name: "Docs Access") }

  before do
    make_admin(admin_identity)
    @staff_person = make_directory_person(staff_identity)
    grant!(@staff_person, group, "view")
  end

  # RoutingError → ApplicationController's rescue_from StandardError → root_path.
  # Pundit::NotAuthorizedError → BaseController's rescue_from → directory_root_path.
  # ExposuresController/AppRequirementsController (not under BaseController) → root_path.

  def expect_denied(method, path, **opts)
    send(method, path, **opts)
    expect(response.status).to be_in([302, 404])
  end

  # ═══════════════════════════════════════════════════════════════
  # 1. ensure_directory_access! gate (BaseController)
  # ═══════════════════════════════════════════════════════════════
  describe "base access gate" do
    it "redirects unauthenticated users to welcome" do
      get directory_root_path
      expect(response).to redirect_to(%r{/welcome})
    end

    it "rejects community identities (no directory person)" do
      sign_in community_identity
      expect_denied(:get, directory_root_path)
    end

    it "rejects a directory person with zero grants" do
      grantless = create(:identity)
      make_directory_person(grantless)
      sign_in grantless
      expect_denied(:get, directory_root_path)
    end

    it "admits a directory person with any grant" do
      sign_in staff_identity
      get directory_root_path
      expect(response).to have_http_status(:ok)
    end

    it "admits directory admins even with no person row" do
      sign_in admin_identity
      get directory_root_path
      expect(response).to have_http_status(:ok)
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # 2. /directory/me — accessible without grants
  # ═══════════════════════════════════════════════════════════════
  describe "GET /directory/me" do
    it "lets a directory person with zero grants see their own access" do
      grantless_identity = create(:identity)
      make_directory_person(grantless_identity)
      sign_in grantless_identity
      get directory_my_access_path
      expect(response).to have_http_status(:ok)
    end

    it "shows a community identity the not-in-directory page, and nothing else" do
      sign_in community_identity
      get directory_my_access_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("directory.my_access.not_in_directory.message")))
      expect(response.body).not_to include("Engineers")
      expect(Directory::Person.where(identity: community_identity)).not_to exist
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # 3. Collection index scoping
  # ═══════════════════════════════════════════════════════════════
  describe "collection scoping" do
    it "delegated user sees only collections they have grants on" do
      _other_group = create(:directory_group, slug: "other", name: "Other Team")
      sign_in staff_identity
      get directory_root_path
      expect(response.body).to include("Engineers")
      expect(response.body).not_to include("Other Team")
    end

    it "admin sees all collections" do
      _other_group = create(:directory_group, slug: "other", name: "Other Team")
      sign_in admin_identity
      get directory_root_path
      expect(response.body).to include("Engineers")
      expect(response.body).to include("Other Team")
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # 4. Collection show: view/manage_members/expose required
  # ═══════════════════════════════════════════════════════════════
  describe "GET /directory/collections/:slug" do
    it "allows access with a view grant" do
      sign_in staff_identity
      get directory_collection_path(group.slug)
      expect(response).to have_http_status(:ok)
    end

    it "denies access to a collection with no grant" do
      sign_in staff_identity
      expect_denied(:get, directory_collection_path(entitlement.slug))
    end

    it "allows access with a manage_members grant" do
      manager_identity = create(:identity)
      manager_person = make_directory_person(manager_identity)
      grant!(manager_person, entitlement, "manage_members")
      sign_in manager_identity
      get directory_collection_path(entitlement.slug)
      expect(response).to have_http_status(:ok)
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # 5. Admin-only routes
  # ═══════════════════════════════════════════════════════════════
  describe "admin-only routes" do
    %i[directory_all_grants_path directory_reports_path directory_health_path directory_view_as_path directory_people_path].each do |path_helper|
      describe "GET #{path_helper}" do
        it "denies non-admin directory user" do
          sign_in staff_identity
          expect_denied(:get, send(path_helper))
        end

        it "admits admin" do
          sign_in admin_identity
          get send(path_helper)
          expect(response).to have_http_status(:ok)
        end
      end
    end

    describe "POST /directory/collections (create)" do
      it "denies non-admin" do
        sign_in staff_identity
        expect_denied(:post, directory_collections_path, params: {
          collection: { name: "Evil", slug: "evil", kind: "group" }
        })
      end

      it "allows admin to create" do
        sign_in admin_identity
        post directory_collections_path, params: {
          collection: { name: "New Group", slug: "new-group", kind: "group" }
        }
        expect(response).to redirect_to(directory_collection_path("new-group"))
        expect(Directory::Collection.find_by(slug: "new-group")).to be_present
      end
    end

    describe "DELETE /directory/collections/:slug" do
      it "denies non-admin" do
        sign_in staff_identity
        expect_denied(:delete, directory_collection_path(group.slug))
      end

      it "allows admin" do
        sign_in admin_identity
        delete directory_collection_path(group.slug)
        expect(response).to redirect_to(directory_root_path)
        expect(Directory::Collection.find_by(slug: "engineers")).to be_nil
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # 6. Memberships: manage_members required
  # ═══════════════════════════════════════════════════════════════
  describe "memberships" do
    let(:manager_identity) { create(:identity) }
    let(:manager_person)   { make_directory_person(manager_identity) }
    let(:target_group)     { create(:directory_group, slug: "managed", name: "Managed") }
    let(:target_person)    { create(:directory_person) }

    before { grant!(manager_person, target_group, "manage_members") }

    describe "POST create (add member)" do
      it "allows holder of manage_members to add a person by email" do
        sign_in manager_identity
        post directory_collection_memberships_path(target_group.slug), params: {
          email: target_person.identity.primary_email
        }
        expect(response).to redirect_to(directory_collection_path(target_group.slug))
        expect(Directory::Membership.where(collection: target_group, member_person: target_person)).to exist
      end

      it "denies a user with only view grant" do
        sign_in staff_identity
        expect_denied(:post, directory_collection_memberships_path(target_group.slug), params: {
          email: target_person.identity.primary_email
        })
      end

      it "shows flash for nonexistent email" do
        sign_in manager_identity
        post directory_collection_memberships_path(target_group.slug), params: {
          email: "nobody@doesnotexist.example"
        }
        expect(response).to redirect_to(directory_collection_path(target_group.slug))
        expect(flash[:alert]).to be_present
      end
    end

    describe "DELETE destroy (remove member)" do
      it "allows holder of manage_members to remove" do
        membership = nil
        Directory.mutate!(cause: "test") do
          membership = Directory::Membership.create!(
            collection: target_group, member_person: target_person,
            created_by_identity_id: manager_identity.id
          )
        end

        sign_in manager_identity
        delete directory_collection_membership_path(target_group.slug, membership)
        expect(response).to redirect_to(directory_collection_path(target_group.slug))
        expect(Directory::Membership.find_by(id: membership.id)).to be_nil
      end
    end

    describe "group nesting escalation prevention" do
      it "requires manage_members on the child group too" do
        child_group = create(:directory_group, slug: "child", name: "Child")
        sign_in manager_identity
        post directory_collection_memberships_path(target_group.slug), params: {
          group_slug: child_group.slug
        }
        # redirected back with a flash, not a success
        expect(response).to redirect_to(directory_collection_path(target_group.slug))
        expect(flash[:alert]).to include("manage")
        expect(Directory::Membership.where(collection: target_group, member_group: child_group)).not_to exist
      end

      it "allows when manager holds manage_members on both groups" do
        child_group = create(:directory_group, slug: "child", name: "Child")
        grant!(manager_person, child_group, "manage_members")
        sign_in manager_identity
        post directory_collection_memberships_path(target_group.slug), params: {
          group_slug: child_group.slug
        }
        expect(response).to redirect_to(directory_collection_path(target_group.slug))
        expect(Directory::Membership.where(collection: target_group, member_group: child_group)).to exist
      end
    end

    describe "entitlement member group restriction" do
      it "non-admin cannot add groups to entitlements" do
        grant!(manager_person, entitlement, "manage_members")
        sign_in manager_identity
        post directory_collection_memberships_path(entitlement.slug), params: {
          group_slug: target_group.slug
        }
        expect(response).to redirect_to(directory_collection_path(entitlement.slug))
        expect(flash[:alert]).to be_present
        expect(Directory::Membership.where(collection: entitlement, member_group: target_group)).not_to exist
      end

      it "admin can add groups to entitlements" do
        sign_in admin_identity
        post directory_collection_memberships_path(entitlement.slug), params: {
          group_slug: target_group.slug
        }
        expect(response).to redirect_to(directory_collection_path(entitlement.slug))
        expect(Directory::Membership.where(collection: entitlement, member_group: target_group)).to exist
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # 7. Grants: admin-only
  # ═══════════════════════════════════════════════════════════════
  describe "grants" do
    let(:grantee) { create(:directory_group, slug: "grantee-direct", name: "Grantee") }

    it "denies non-admin from creating grants" do
      sign_in staff_identity
      expect_denied(:post, directory_collection_grants_path(group.slug), params: {
        grantee_group_slug: grantee.slug, permission: "view"
      })
    end

    it "allows admin to create grants" do
      sign_in admin_identity
      post directory_collection_grants_path(group.slug), params: {
        grantee_group_slug: grantee.slug, permission: "view"
      }
      expect(response).to redirect_to(directory_collection_path(group.slug))
      expect(Directory::Grant.where(grantee_group: grantee, target_collection: group, permission: "view")).to exist
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # 8. Person show: requires shared-collection visibility
  # ═══════════════════════════════════════════════════════════════
  describe "GET /directory/people/:id" do
    it "denies when viewer has no overlapping collection with the target" do
      other_person = make_directory_person(create(:identity))
      sign_in staff_identity
      expect_denied(:get, directory_person_path(other_person))
    end

    it "allows when viewer shares a collection via grants" do
      visible_person = make_directory_person(create(:identity))
      Directory.mutate!(cause: "test") do
        Directory::Membership.create!(collection: group, member_person: visible_person, created_by_identity_id: admin_identity.id)
      end

      sign_in staff_identity
      get directory_person_path(visible_person)
      expect(response).to have_http_status(:ok)
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # 9. Search: scoped to visible collections/people
  # ═══════════════════════════════════════════════════════════════
  describe "GET /directory/search" do
    it "does not leak invisible collections" do
      _secret = create(:directory_group, slug: "secret", name: "Secret Ops Group")
      sign_in staff_identity
      get directory_search_path, params: { q: "Secret" }
      expect(response.body).not_to include("Secret Ops Group")
    end

    it "shows visible collections" do
      sign_in staff_identity
      get directory_search_path, params: { q: "Engineer" }
      expect(response.body).to include("Engineers")
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # 10. Picker: requires manage_members somewhere
  # ═══════════════════════════════════════════════════════════════
  describe "GET /directory/picker/search" do
    it "denies a user with only view grants" do
      sign_in staff_identity
      expect_denied(:get, directory_picker_search_path, params: { q: "test", scope: "people" })
    end

    it "allows a user with manage_members" do
      managed = create(:directory_group, slug: "mm-test", name: "MM Test")
      grant!(@staff_person, managed, "manage_members")
      sign_in staff_identity
      get directory_picker_search_path, params: { q: "test", scope: "people" }
      expect(response).to have_http_status(:ok)
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # 11. Exposures: app owner + expose + hq_official
  # ═══════════════════════════════════════════════════════════════
  describe "exposures" do
    let(:oauth_app) { create(:program, owner_identity: admin_identity, trust_level: :hq_official) }

    it "denies when not app owner" do
      sign_in staff_identity
      expect_denied(:post, directory_exposures_path, params: {
        app_id: oauth_app.id, entitlement_slug: entitlement.slug, claim_name: "test"
      })
    end

    it "denies when app is community trust level" do
      community_app = create(:program, trust_level: :community_untrusted, owner_identity: admin_identity, scopes: "openid profile")
      sign_in admin_identity
      expect_denied(:post, directory_exposures_path, params: {
        app_id: community_app.id, entitlement_slug: entitlement.slug, claim_name: "test"
      })
    end

    it "allows admin app owner with expose permission on hq_official app" do
      sign_in admin_identity
      post directory_exposures_path, params: {
        app_id: oauth_app.id, entitlement_slug: entitlement.slug, claim_name: "staff"
      }
      expect(response).to redirect_to(developer_app_path(oauth_app))
      expect(Directory::Exposure.where(app: oauth_app, entitlement: entitlement)).to exist
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # 12. App requirements: app owner + expose + hq_official / AND gate for removal
  # ═══════════════════════════════════════════════════════════════
  describe "app requirements" do
    let(:oauth_app) { create(:program, owner_identity: admin_identity, trust_level: :hq_official) }

    it "denies non-owner from adding" do
      sign_in staff_identity
      expect_denied(:post, directory_app_requirements_path, params: {
        app_id: oauth_app.id, entitlement_slug: entitlement.slug
      })
    end

    it "allows admin owner to add requirement" do
      sign_in admin_identity
      post directory_app_requirements_path, params: {
        app_id: oauth_app.id, entitlement_slug: entitlement.slug
      }
      expect(response).to redirect_to(developer_app_path(oauth_app))
      expect(Directory::AppRequirement.where(app: oauth_app, entitlement: entitlement)).to exist
    end

    describe "removing requirements (AND gate: owner AND expose/admin)" do
      before do
        Directory::AppRequirement.create!(app: oauth_app, entitlement: entitlement)
      end

      it "denies someone with expose but not app owner" do
        exposer_identity = create(:identity)
        exposer_person = make_directory_person(exposer_identity)
        grant!(exposer_person, entitlement, "expose")
        sign_in exposer_identity
        expect_denied(:delete, directory_app_requirement_path(entitlement), params: { app_id: oauth_app.id })
      end

      it "allows admin owner to remove" do
        sign_in admin_identity
        delete directory_app_requirement_path(entitlement), params: { app_id: oauth_app.id }
        expect(response).to redirect_to(developer_app_path(oauth_app))
        expect(Directory::AppRequirement.where(app: oauth_app, entitlement: entitlement)).not_to exist
      end
    end
  end
end
