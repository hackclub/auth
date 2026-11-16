# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Directory activity owner links", type: :request do
  let(:viewer) { create(:directory_person) }
  let(:group) { create(:directory_group, slug: "crew") }
  let(:visible_owner) { create(:directory_person) }
  let(:hidden_owner) { create(:directory_person) }

  before do
    grantee = create(:directory_group)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: grantee, member_person: viewer)
      Directory::Membership.create!(collection: group, member_person: visible_owner)
      Directory::Grant.create!(grantee_group: grantee, target_collection: group, permission: "view")
    end
    [ visible_owner, hidden_owner ].each do |owner|
      group.create_activity :member_added, owner: owner.identity, parameters: { member_name: "someone", member_type: "person" }
    end
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(viewer.identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  it "links owners the viewer can open and leaves the rest as plain names" do
    get activity_directory_collection_path(group.slug)

    expect(response).to have_http_status(:ok)
    page = response.parsed_body
    expect(page.at_css(%(a[href="#{directory_person_path(visible_owner)}"]))).to be_present
    expect(page.at_css(%(a[href="#{directory_person_path(hidden_owner)}"]))).to be_nil
    expect(page.text).to include(hidden_owner.identity.first_name)
    expect(page.css("a[href^='/backend/']")).to be_empty
  end

  it "shows a backend user owner as their identity, with no backend link or username" do
    staffer = create(:identity, first_name: "Staff", last_name: "Person")
    backend_user = create(:backend_user, identity: staffer, username: "secret-staff-handle", super_admin: true)
    group.create_activity :member_removed, owner: backend_user, parameters: { member_name: "someone", member_type: "person" }

    get activity_directory_collection_path(group.slug)

    page = response.parsed_body
    expect(page.css("a[href^='/backend/']")).to be_empty
    expect(page.text).not_to include("secret-staff-handle")
    expect(page.text).to include("Staff Person")
  end

  it "shows a deleted owner as a deleted user, not the system" do
    gone = create(:identity)
    group.create_activity :member_added, owner: gone, parameters: { member_name: "someone", member_type: "person" }
    gone.destroy

    get activity_directory_collection_path(group.slug)

    expect(response.parsed_body.text).to include("[deleted user]")
  end
end
