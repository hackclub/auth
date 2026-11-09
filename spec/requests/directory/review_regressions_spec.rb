# frozen_string_literal: true

require "rails_helper"

# Regressions from the directory-services review: each describe is one bug that shipped.
RSpec.describe "Directory review regressions", type: :request do
  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  def make_admin(identity)
    bu = Backend::User.find_by(identity: identity) || create(:backend_user, identity: identity)
    bu.update!(directory_services_admin: true)
    identity.reload
    bu
  end

  def grant!(person, collection, permission)
    grantee = create(:directory_group)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: grantee, member_person: person, created_by_identity_id: person.identity_id)
      Directory::Grant.create!(grantee_group: grantee, target_collection: collection, permission: permission, created_by_identity_id: person.identity_id)
    end
    grantee
  end

  def add!(collection, person: nil, group: nil, expires_at: nil)
    m = nil
    Directory.mutate!(cause: "test") do
      m = Directory::Membership.create!(collection:, member_person: person, member_group: group, expires_at:,
                                        created_by_identity_id: admin_identity.id)
    end
    m
  end

  let(:admin_identity) { create(:identity) }
  let(:group) { create(:directory_group, slug: "crew", name: "Crew") }
  let(:person) { create(:directory_person) }

  before { make_admin(admin_identity) }

  describe "people#show app access" do
    it "doesn't name entitlements the viewer can't see" do
      viewer = create(:directory_person)
      visible_ent = create(:directory_entitlement, slug: "visible-ent", name: "Visible Ent")
      hidden_ent = create(:directory_entitlement, slug: "hidden-ent", name: "Hidden Secret Ent")
      app = create(:program, name: "Some App")
      Directory::Exposure.create!(app: app, entitlement: visible_ent, claim_name: "visible_claim")
      Directory::Exposure.create!(app: app, entitlement: hidden_ent, claim_name: "hidden_claim")
      add!(group, person: person)
      add!(visible_ent, person: person)
      add!(hidden_ent, person: person)
      grant!(viewer, group, "view")
      grant!(viewer, visible_ent, "view")

      sign_in viewer.identity
      get directory_person_path(person)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Visible Ent", "visible_claim")
      expect(response.body).not_to include("Hidden Secret Ent")
      expect(response.body).not_to include("hidden_claim")
      expect(response.body).not_to include("hidden-ent")
    end
  end

  describe "email lookup audit" do
    let(:manager) { create(:directory_person) }

    before { grant!(manager, group, "manage_members") }

    def misses
      PublicActivity::Activity.where(key: "directory_collection.email_lookup_miss", owner: manager.identity)
    end

    it "records a miss for single add-by-email" do
      sign_in manager.identity
      expect { post directory_collection_memberships_path(group.slug), params: { email: "ghost@nowhere.example" } }
        .to change { misses.count }.by(1)
      expect(flash[:alert]).to eq(I18n.t("directory.flash.email_not_found"))
    end

    it "shows misses to managers but not to view-only users" do
      group.create_activity :email_lookup_miss, owner: manager.identity, params: { email: "ghost@nowhere.example" }
      viewer = create(:directory_person)
      grant!(viewer, group, "view")

      sign_in viewer.identity
      get directory_collection_path(group.slug)
      expect(response.body).not_to include("ghost@nowhere")
      get activity_directory_collection_path(group.slug)
      expect(response.body).not_to include("ghost@nowhere")

      sign_in manager.identity
      get activity_directory_collection_path(group.slug)
      expect(response.body).to include("ghost@nowhere")
    end
  end

  describe "re-adding an expired group" do
    it "replaces the expired nesting row" do
      child = create(:directory_group, slug: "child")
      m = add!(group, group: child, expires_at: 1.day.from_now)
      m.update_columns(expires_at: 1.hour.ago)
      Directory::Rebuild.call(cause: "test-expire")

      sign_in admin_identity
      post directory_collection_memberships_path(group.slug), params: { group_slug: "child" }

      expect(flash[:notice]).to eq(I18n.t("directory.flash.member_added"))
      expect(Directory::Membership.active.where(collection: group, member_group: child)).to exist
      expect(Directory::Membership.where(collection: group, member_group: child).count).to eq(1)
    end
  end

  describe "grants" do
    let!(:grantee) { create(:directory_group, slug: "grantee") }

    before { sign_in admin_identity }

    def add_grant(recursive: false)
      post directory_collection_grants_path(group.slug),
        params: { grantee_group_slug: "grantee", permission: "manage_members", recursive: recursive ? "1" : "0" }
    end

    it "refuses an exact duplicate instead of 500ing" do
      add_grant
      add_grant
      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq(I18n.t("directory.flash.grant_already_exists"))
      expect(Directory::Grant.where(grantee_group: grantee, target_collection: group).count).to eq(1)
    end

    it "flips recursive on an existing grant" do
      add_grant
      add_grant(recursive: true)
      expect(flash[:notice]).to eq(I18n.t("directory.flash.grant_updated"))
      expect(Directory::Grant.find_by!(grantee_group: grantee, target_collection: group)).to be_recursive
    end

    it "doesn't strip recursion when re-added with the box unticked" do
      add_grant(recursive: true)
      add_grant
      expect(flash[:alert]).to eq(I18n.t("directory.flash.grant_already_exists"))
      expect(Directory::Grant.find_by!(grantee_group: grantee, target_collection: group)).to be_recursive
    end

    it "toggles recursion from the grant row" do
      add_grant(recursive: true)
      grant = Directory::Grant.find_by!(grantee_group: grantee, target_collection: group)

      patch directory_collection_grant_path(group.slug, grant), params: { recursive: "0" }
      expect(grant.reload).not_to be_recursive

      patch directory_collection_grant_path(group.slug, grant), params: { recursive: "1" }
      expect(grant.reload).to be_recursive
    end

    it "doesn't let non-admins toggle recursion" do
      add_grant(recursive: true)
      grant = Directory::Grant.find_by!(grantee_group: grantee, target_collection: group)
      sign_in create(:identity)

      patch directory_collection_grant_path(group.slug, grant), params: { recursive: "0" }
      expect(grant.reload).to be_recursive
    end

    it "redirects with an alert when the target collection doesn't exist" do
      post directory_collection_grants_path("no-such-thing"), params: { grantee_group_slug: "grantee", permission: "view" }
      expect(response).to redirect_to(directory_root_path)
    end
  end

  describe "membership create on a missing collection" do
    it "redirects instead of raising on @collection.slug" do
      sign_in admin_identity
      post directory_collection_memberships_path("Not A Slug"), params: { member_person_id: person.id }
      expect(response).to redirect_to(directory_root_path)
      expect(flash[:alert]).to eq(I18n.t("directory.flash.member_not_found"))
    end

    it "404s for non-admins, same as a collection they can't see" do
      manager = create(:directory_person)
      grant!(manager, group, "manage_members")
      sign_in manager.identity
      post directory_collection_memberships_path("nope"), params: { member_person_id: person.id }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "expires_at parsing" do
    before { sign_in admin_identity }

    it "rejects dates that Time.zone.parse would roll over" do
      post directory_collection_memberships_path(group.slug), params: { email: person.primary_email, expires_at: "2099-02-30" }
      expect(flash[:alert]).to eq(I18n.t("directory.flash.invalid_expires_at"))
      expect(Directory::Membership.where(collection: group)).not_to exist
    end

    it "accepts a valid ISO date" do
      post directory_collection_memberships_path(group.slug), params: { email: person.primary_email, expires_at: "2099-03-01" }
      expect(Directory::Membership.find_by!(collection: group).expires_at).to eq(Time.zone.parse("2099-03-01"))
    end

    it "says a past expiry is in the past, not that everyone was not found" do
      post batch_create_directory_collection_memberships_path(group.slug),
        params: { identifiers: [ person.primary_email ], expires_at: "2001-01-01" }
      expect(flash[:alert]).to eq(I18n.t("directory.flash.expires_at_in_past"))
      expect(flash[:notice]).to be_blank
    end
  end

  describe "kbar" do
    it "doesn't 500 on a query of only bangs" do
      sign_in admin_identity
      get directory_search_kbar_path, params: { q: "!!" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "member counts" do
    it "doesn't count nested groups as direct members" do
      ent = create(:directory_entitlement)
      3.times { add!(ent, group: create(:directory_group)) }
      expect(ent.direct_member_count).to eq(0)
      expect(ent.effective_member_count).to eq(0)

      sign_in admin_identity
      get directory_collection_path(ent.slug)
      expect(response.body).not_to include("nested)")
      get directory_root_path
      expect(response.body).not_to include("+-")
    end
  end

  describe "removal consequences on a group page" do
    it "computes them for the rows the members list renders" do
      sign_in admin_identity
      parent = create(:directory_group, slug: "parent", name: "Parent")
      add!(parent, group: group)
      add!(group, person: person)
      add!(parent, person: person)

      expect(Directory::Consequence).to receive(:batch_removal_summaries) do |memberships:, collection:, viewer:|
        expect(memberships.map(&:id)).to match_array(Directory::Membership.where(collection: group).pluck(:id))
        {}
      end
      get directory_collection_path(group.slug)
    end
  end

  describe "reserved slugs" do
    it "won't create a collection whose slug is a route" do
      expect(Directory::Collection.new(slug: "new", name: "New", kind: "group")).not_to be_valid
    end
  end
end
