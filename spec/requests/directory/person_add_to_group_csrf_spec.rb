# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Adding a person to a group from their page", type: :request do
  let(:admin) { create(:identity) }
  let(:person) { create(:directory_person) }
  let!(:team) { create(:directory_group, slug: "team") }

  before do
    create(:backend_user, identity: admin, directory_services_admin: true)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(admin.reload)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  around do |example|
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  it "accepts the form's token once the action points at the picked group" do
    get directory_person_path(person)
    token = response.parsed_body.at_css("#add-to-group-form input[name=authenticity_token]")["value"]

    post directory_collection_memberships_path("team"),
      params: { authenticity_token: token, collection_slug: "team", member_person_id: person.id }

    expect(response).to have_http_status(:found)
    expect(team.memberships.where(member_person: person)).to exist
  end
end
