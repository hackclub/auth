# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Directory picker people search", type: :request do
  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  let(:manager) { create(:directory_person) }
  let(:team) { create(:directory_group, slug: "team") }
  let(:teammate) { create(:directory_person, identity: create(:identity, first_name: "Zorblax", last_name: "Visible")) }
  let!(:stranger) { create(:directory_person, identity: create(:identity, first_name: "Zorblax", last_name: "Hidden", primary_email: "zorblax.hidden@example.com")) }

  before do
    grantee = create(:directory_group)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: grantee, member_person: manager)
      Directory::Membership.create!(collection: team, member_person: teammate)
      Directory::Grant.create!(grantee_group: grantee, target_collection: team, permission: "manage_members")
    end
    sign_in manager.identity
  end

  def labels(q)
    get directory_picker_search_path, params: { q: q, scope: "people" }
    JSON.parse(response.body).map { |r| r["label"] }
  end

  it "only finds people the manager can see by name" do
    expect(labels("Zorblax")).to contain_exactly("Zorblax Visible")
  end

  it "still resolves an exact email for someone they can't see yet" do
    expect(labels("zorblax.hidden@example.com")).to contain_exactly("Zorblax Hidden")
  end
end
