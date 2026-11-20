# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Grant activity names only grantee groups the viewer can see", type: :request do
  let(:viewer) { create(:directory_person) }
  let(:granter) { create(:directory_person) }
  let(:staff) { create(:directory_group, slug: "staff", name: "Staff") }
  let(:hidden) { create(:directory_group, slug: "board-confidential", name: "Board Confidential") }

  before do
    viewers = create(:directory_group)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: viewers, member_person: viewer)
      Directory::Membership.create!(collection: staff, member_person: granter)
      Directory::Grant.create!(grantee_group: viewers, target_collection: staff, permission: "view")
      Directory::Grant.create!(grantee_group: hidden, target_collection: staff, permission: "manage_members")
    end
    PublicActivity::Activity.where(key: "directory_grant.create").update_all(owner_type: "Identity", owner_id: granter.identity_id)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(viewer.identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  it "doesn't name a hidden grantee group on the granter's page" do
    get directory_person_path(granter)

    expect(response).to have_http_status(:ok)
    text = response.parsed_body.text
    expect(text).to include("manage_members")
    expect(text).not_to include("Board Confidential")
    expect(text).to include(I18n.t("directory.hidden_group"))
  end
end
