# frozen_string_literal: true

require "rails_helper"

# The person page's activity feed is directory activity only (SPEC §8.4): never the
# identity's account-wide audit log, and for non-admins only rows tied to a collection
# the viewer can see.
RSpec.describe "Directory person page activity feed", type: :request do
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
    grantee = create(:directory_group, slug: "g-#{person.id}-#{collection.id}-#{permission.tr('_', '-')}")
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: grantee, member_person: person, created_by_identity_id: person.identity_id)
      Directory::Grant.create!(grantee_group: grantee, target_collection: collection, permission: permission, created_by_identity_id: person.identity_id)
    end
    grantee
  end

  def add_member!(collection, person, by:)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: collection, member_person: person, created_by_identity_id: by.id)
    end
  end

  # Tracked callbacks take their owner from the controller PublicActivity stored for the
  # request; stand one in so rows written here are attributed like a real request's.
  def acting_as(identity)
    PublicActivity.set_controller(Struct.new(:user_for_public_activity).new(identity))
    yield
  ensure
    PublicActivity.set_controller(nil)
  end

  def feed = controller.instance_variable_get(:@activities).to_a

  let(:directory_types) do
    %w[Directory::Collection Directory::Person Directory::Membership Directory::Grant Directory::Exposure]
  end

  let(:admin_identity)  { create(:identity) }
  let(:viewer_identity) { create(:identity) }
  let(:member_identity) { create(:identity, first_name: "Pat", last_name: "Member") }

  let(:visible) { create(:directory_group, slug: "visible-team", name: "Visible Team") }
  let(:hidden)  { create(:directory_group, slug: "hidden-team", name: "Hidden Skunkworks") }

  let!(:viewer) { create(:directory_person, identity: viewer_identity) }
  let!(:member) { create(:directory_person, identity: member_identity) }

  let!(:added_to_visible) do
    add_member!(visible, member, by: admin_identity)
    PublicActivity::Activity.find_by!(key: "directory_collection.member_added", trackable: visible, recipient: member)
  end

  # Account-wide rows the member's identity owns. None of these are directory activity.
  let!(:account_rows) do
    member_identity.create_activity(:legal_name_updated, owner: member_identity, recipient: member_identity,
      parameters: { old_name: "Pat Member", new_name: "Patricia Secretlegal" })
    IdentitySession.create!(identity: member_identity, session_token: SecureRandom.hex(32),
      expires_at: 1.day.from_now, device_info: "Secretfox 128", os_info: "SecretOS 9")
    create(:oauth_token, resource_owner: member_identity, application: create(:program, name: "Secret Oauth App"))

    PublicActivity::Activity.where(owner: member_identity).where.not(trackable_type: directory_types).to_a
  end

  before do
    make_admin(admin_identity)
    grant!(viewer, visible, "view")
  end

  it "builds the account-wide rows the leak was made of" do
    expect(account_rows.map(&:key)).to contain_exactly(
      "identity.legal_name_updated", "identity_session.create", "oauth_token.create"
    )
  end

  context "as a non-admin with view on a collection the person is in" do
    it "shows directory activity on that collection but none of the identity's account activity" do
      sign_in viewer_identity
      get directory_person_path(member)

      expect(response).to have_http_status(:ok)
      expect(feed & account_rows).to be_empty
      expect(feed.map(&:trackable_type)).to all(be_in(directory_types))
      expect(feed).to include(added_to_visible)

      expect(response.body).not_to include("Secretlegal")
      expect(response.body).not_to include("Secretfox")
      expect(response.body).not_to include("Secret Oauth App")
    end

    it "hides the person's manager actions on collections the viewer can't see" do
      grant!(member, hidden, "manage_members")
      quinn = create(:identity, first_name: "Quinn", last_name: "Hiddenperson")
      acting_as(member_identity) do
        quinn_person = create(:directory_person, identity: quinn)
        add_member!(hidden, quinn_person, by: member_identity)
      end
      hidden.create_activity(:email_lookup_miss, owner: member_identity, params: { email: "ghost@nowhere.example" })

      hidden_rows = PublicActivity::Activity.where(owner: member_identity, trackable_type: directory_types).to_a
      expect(hidden_rows.map(&:key)).to include(
        "directory_person.create", "directory_membership.create",
        "directory_collection.member_added", "directory_collection.email_lookup_miss"
      )

      sign_in viewer_identity
      get directory_person_path(member)

      expect(response).to have_http_status(:ok)
      expect(feed & hidden_rows).to be_empty
      expect(feed).to include(added_to_visible)
      expect(response.body).not_to include("Quinn Hiddenperson")
      expect(response.body).not_to include("ghost@nowhere.example")
    end

    it "places exposure rows by their entitlement" do
      shown_entitlement = create(:directory_entitlement, slug: "shown-access")
      hidden_entitlement = create(:directory_entitlement, slug: "hidden-access")
      grant!(viewer, shown_entitlement, "view")
      app = create(:program)
      acting_as(member_identity) do
        Directory::Exposure.create!(app: app, entitlement: shown_entitlement, claim_name: "shown")
        Directory::Exposure.create!(app: app, entitlement: hidden_entitlement, claim_name: "hidden")
      end
      shown, hidden_exposure = %w[shown hidden].map do |claim|
        PublicActivity::Activity.find_by!(key: "directory_exposure.create", trackable: Directory::Exposure.find_by!(claim_name: claim))
      end

      sign_in viewer_identity
      get directory_person_path(member)

      expect(feed).not_to include(hidden_exposure)
      expect(feed).to include(shown)
    end

    it "shows the person's manager actions on collections the viewer can see, including removals" do
      grant!(member, visible, "manage_members")
      rowan = create(:identity, first_name: "Rowan", last_name: "Visibleperson")
      acting_as(member_identity) do
        rowan_person = create(:directory_person, identity: rowan)
        add_member!(visible, rowan_person, by: member_identity)
        Directory.mutate!(cause: "test") { Directory::Membership.find_by!(member_person: rowan_person).destroy! }
      end

      member_added = PublicActivity::Activity.find_by!(key: "directory_collection.member_added", trackable: visible, owner: member_identity)
      added = PublicActivity::Activity.find_by!(key: "directory_membership.create", owner: member_identity, recipient: visible)
      removed = PublicActivity::Activity.find_by!(key: "directory_membership.destroy", owner: member_identity, recipient: visible)
      expect(removed.trackable).to be_nil

      sign_in viewer_identity
      get directory_person_path(member)

      # the membership is gone, but the removal row still names its collection as recipient
      expect(feed).to include(member_added, added, removed)
    end

    it "hides rows whose record is gone and can't be placed in a visible collection" do
      grantee = create(:directory_group, slug: "gone-grantee")
      acting_as(member_identity) do
        Directory.mutate!(cause: "test") do
          Directory::Grant.create!(grantee_group: grantee, target_collection: hidden, permission: "view").destroy!
        end
      end
      gone = PublicActivity::Activity.where(trackable_type: "Directory::Grant", owner: member_identity).to_a
      expect(gone.map(&:key)).to contain_exactly("directory_grant.create", "directory_grant.destroy")

      sign_in viewer_identity
      get directory_person_path(member)

      expect(feed & gone).to be_empty
      expect(response.body).not_to include("Hidden Skunkworks")
    end

    it "filters before the 20-row window, so hidden rows can't crowd out visible ones" do
      25.times do |i|
        hidden.create_activity(:email_lookup_miss, owner: member_identity, params: { email: "miss#{i}@nowhere.example" })
      end

      sign_in viewer_identity
      get directory_person_path(member)

      expect(feed).to include(added_to_visible)
    end
  end

  context "as a directory admin" do
    it "shows all of the person's directory activity and none of their account activity" do
      grant!(member, hidden, "manage_members")
      hidden.create_activity(:email_lookup_miss, owner: member_identity, params: { email: "ghost@nowhere.example" })
      lookup_miss = PublicActivity::Activity.find_by!(key: "directory_collection.email_lookup_miss")

      sign_in admin_identity
      get directory_person_path(member)

      expect(response).to have_http_status(:ok)
      expect(feed & account_rows).to be_empty
      expect(feed.map(&:trackable_type)).to all(be_in(directory_types))
      expect(feed).to include(added_to_visible, lookup_miss)

      expect(response.body).not_to include("Secretlegal")
      expect(response.body).not_to include("Secretfox")
      expect(response.body).not_to include("Secret Oauth App")
    end
  end
end
