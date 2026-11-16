# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Directory docs", type: :request do
  CURIOUS = "hey! fine that you're curious"

  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  def manager
    person = create(:directory_person)
    grantee = create(:directory_group)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: grantee, member_person: person)
      Directory::Grant.create!(grantee_group: grantee, target_collection: create(:directory_group), permission: "manage_members")
    end
    person.identity
  end

  %w[directory-teams directory-app-builders].each do |slug|
    it "renders #{slug} for someone who manages a group, listed and without the banner" do
      sign_in manager
      get doc_path(slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to match(/translation[ _]missing/i)
      expect(response.body).not_to include(CURIOUS)
      expect(response.parsed_body.css(".docs-nav a").map { |a| a["href"] }).to include(doc_path("directory-teams"))
    end

    it "shows #{slug} with the banner, and leaves it out of the nav, for everyone else" do
      sign_in create(:identity)
      get doc_path(slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(CURIOUS)
      expect(response.parsed_body.css(".docs-nav a").map { |a| a["href"] }).not_to include(doc_path("directory-teams"))
    end
  end

  it "shows the banner when logged out" do
    get doc_path("directory-teams")
    expect(response.body).to include(CURIOUS)
  end

  it "lists them for a directory admin" do
    admin = create(:identity)
    create(:backend_user, identity: admin, directory_services_admin: true)
    sign_in admin.reload
    get doc_path("welcome")
    expect(response.parsed_body.css(".docs-nav a").map { |a| a["href"] }).to include(doc_path("directory-app-builders"))
  end
end
