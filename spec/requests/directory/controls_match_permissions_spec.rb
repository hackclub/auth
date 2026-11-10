# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Directory controls only show where the server would allow them", type: :request do
  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  def grant!(person, collection, permission)
    grantee = create(:directory_group)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: grantee, member_person: person)
      Directory::Grant.create!(grantee_group: grantee, target_collection: collection, permission: permission)
    end
  end

  it "hides remove and expiry controls on group rows the manager can't change" do
    manager = create(:directory_person)
    team = create(:directory_group, slug: "team")
    managed_child = create(:directory_group, slug: "managed-child")
    other_child = create(:directory_group, slug: "other-child")
    managed_edge = other_edge = nil
    Directory.mutate!(cause: "test") do
      managed_edge = Directory::Membership.create!(collection: team, member_group: managed_child)
      other_edge = Directory::Membership.create!(collection: team, member_group: other_child)
    end
    grant!(manager, team, "manage_members")
    grant!(manager, managed_child, "manage_members")
    grant!(manager, other_child, "view")
    sign_in manager.identity

    get directory_collection_path("team")

    page = response.parsed_body
    expect(page.at_css(%(form[action="#{directory_collection_membership_path('team', managed_edge)}"]))).to be_present
    expect(page.at_css(%(form[action="#{directory_collection_membership_path('team', other_edge)}"]))).to be_nil
  end

  it "doesn't offer the wire forms to an app owner whose only expose grants are on groups" do
    owner = create(:directory_person)
    app = create(:program, :with_groups, trust_level: :hq_official, owner_identity: owner.identity)
    grant!(owner, create(:directory_group), "expose")
    sign_in owner.identity

    get developer_app_path(app)

    expect(response.body).not_to include(directory_exposures_path)
  end
end
