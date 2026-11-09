# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Directory my access page", type: :request do
  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  it "renders a translated breadcrumb for directory people" do
    sign_in create(:directory_person).identity

    get directory_my_access_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to match(/translation[ _]missing/i)
  end

  it "renders a translated breadcrumb for identities outside the directory" do
    sign_in create(:identity)

    get directory_my_access_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to match(/translation[ _]missing/i)
  end

  it "doesn't link a grantless member to pages that 404 for them" do
    person = create(:directory_person)
    team = create(:directory_group)
    Directory.mutate!(cause: "test") { Directory::Membership.create!(collection: team, member_person: person) }
    sign_in person.identity

    get directory_my_access_path

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.css(%(a[href="#{directory_root_path}"]))).to be_empty
  end

  it "only links collections the person can open" do
    person = create(:directory_person)
    hidden = create(:directory_group, slug: "hidden-team", name: "Hidden Team")
    visible = create(:directory_group, slug: "visible-team", name: "Visible Team")
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: hidden, member_person: person)
      Directory::Membership.create!(collection: visible, member_person: person)
      Directory::Grant.create!(grantee_group: visible, target_collection: visible, permission: "view")
    end
    sign_in person.identity

    get directory_my_access_path

    expect(response.body).to include("Hidden Team")
    expect(response.body).not_to include(directory_collection_path("hidden-team"))
    expect(response.body).to include(directory_collection_path("visible-team"))
  end
end
