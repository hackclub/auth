# frozen_string_literal: true

require "rails_helper"

# a write aimed at something the actor can't see answers exactly like one aimed at nothing,
# so slugs, requirements and record ids can't be probed through write endpoints
RSpec.describe "Directory writes against things the actor can't see", type: :request do
  let(:actor) { create(:directory_person) }
  let(:visible) { create(:directory_group, slug: "visible") }
  let!(:hidden) { create(:directory_entitlement, slug: "hidden") }
  let(:other_group) { create(:directory_group, slug: "elsewhere") }

  before do
    grantee = create(:directory_group)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: grantee, member_person: actor)
      Directory::Grant.create!(grantee_group: grantee, target_collection: visible, permission: "view")
    end
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(actor.identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  def statuses_for(slug_or_record)
    yield(slug_or_record)
    response.status
  end

  it "grants#create, memberships#create and #batch_create answer a hidden slug like a missing one" do
    {
      grants: ->(slug) { post directory_collection_grants_path(slug), params: { grantee_group_slug: "visible", permission: "view" } },
      membership: ->(slug) { post directory_collection_memberships_path(slug), params: { email: "x@example.com" } },
      batch: ->(slug) { post batch_create_directory_collection_memberships_path(slug), params: { identifiers: [ "x@example.com" ] } }
    }.each do |name, request|
      request.call("hidden")
      hidden_status = response.status
      request.call("does-not-exist")
      expect(hidden_status).to eq(response.status), name.to_s
      expect(hidden_status).to eq(404), name.to_s
    end
  end

  it "collections#update answers a hidden slug like a missing one" do
    patch directory_collection_path("hidden"), params: { collection: { name: "x" } }
    hidden_status = response.status
    patch directory_collection_path("does-not-exist"), params: { collection: { name: "x" } }

    expect(hidden_status).to eq(response.status)
    expect(hidden_status).to eq(404)
  end

  it "membership and grant ids on hidden collections 404 like missing ids" do
    membership = nil
    grant = nil
    Directory.mutate!(cause: "test") do
      membership = Directory::Membership.create!(collection: hidden, member_person: create(:directory_person))
      grant = Directory::Grant.create!(grantee_group: other_group, target_collection: hidden, permission: "view")
    end

    delete directory_collection_membership_path("hidden", membership)
    expect(response).to have_http_status(:not_found)
    patch directory_collection_membership_path("hidden", membership), params: { expires_at: "" }
    expect(response).to have_http_status(:not_found)
    delete directory_collection_grant_path("hidden", grant)
    expect(response).to have_http_status(:not_found)
    patch directory_collection_grant_path("hidden", grant), params: { recursive: "1" }
    expect(response).to have_http_status(:not_found)
    expect(Directory::Membership.exists?(membership.id)).to be(true)
  end

  it "app_requirements#destroy answers the same whether or not the hidden entitlement is required" do
    app = create(:program, :with_groups, trust_level: :hq_official)
    delete directory_app_requirement_path("hidden"), params: { app_id: app.id }
    without = response.status
    Directory::AppRequirement.create!(app: app, entitlement: hidden)
    delete directory_app_requirement_path("hidden"), params: { app_id: app.id }

    expect(response.status).to eq(without)
    expect(Directory::AppRequirement.where(app: app, entitlement: hidden)).to exist
  end
end
