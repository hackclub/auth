# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Directory slugs can't be probed", type: :request do
  def grant!(person, collection, permission)
    grantee = create(:directory_group)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: grantee, member_person: person)
      Directory::Grant.create!(grantee_group: grantee, target_collection: collection, permission: permission)
    end
  end

  let(:actor) { create(:directory_person) }
  let(:team) { create(:directory_group, slug: "team") }
  let!(:hidden_group) { create(:directory_group, slug: "hidden-group") }
  let!(:hidden_ent) { create(:directory_entitlement, slug: "hidden-ent") }
  let(:oauth_app) { create(:program, owner_identity: actor.identity, trust_level: :hq_official) }

  before do
    grant!(actor, team, "manage_members")
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(actor.identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  def outcome
    [ response.status, flash[:alert] ]
  end

  it "answers a hidden group like a missing one when nesting by slug" do
    post directory_collection_memberships_path(team.slug), params: { group_slug: "hidden-group" }
    hidden = outcome
    post directory_collection_memberships_path(team.slug), params: { group_slug: "no-such-group" }

    expect(hidden).to eq(outcome)
    expect(Directory::Membership.where(collection: team, member_group: hidden_group)).not_to exist
  end

  it "answers a hidden entitlement like a missing one when wiring an app" do
    post directory_exposures_path, params: { app_id: oauth_app.id, entitlement_slug: "hidden-ent", claim_name: "x" }
    hidden = outcome
    post directory_exposures_path, params: { app_id: oauth_app.id, entitlement_slug: "no-such-ent", claim_name: "x" }
    expect(hidden).to eq(outcome)

    post directory_app_requirements_path, params: { app_id: oauth_app.id, entitlement_slug: "hidden-ent" }
    hidden = outcome
    post directory_app_requirements_path, params: { app_id: oauth_app.id, entitlement_slug: "no-such-ent" }
    expect(hidden).to eq(outcome)
  end
end
