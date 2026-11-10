# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Directory admin needs a 2FA'd session", type: :request do
  let(:admin) do
    create(:identity).tap do |i|
      create(:backend_user, identity: i, directory_services_admin: true)
      i.reload
    end
  end
  let(:oauth_app) { create(:program, owner_identity: create(:identity), trust_level: :hq_official) }
  let(:entitlement) { create(:directory_entitlement, slug: "docs-access") }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(admin)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  context "without 2FA" do
    before { allow_any_instance_of(ApplicationController).to receive(:two_factor_session?).and_return(false) }

    it "isn't a directory admin" do
      get directory_root_path
      expect(response).to have_http_status(:not_found)

      expect {
        post directory_collections_path, params: { collection: { name: "X", slug: "x-coll", kind: "group" } }
      }.not_to change(Directory::Collection, :count)

      expect {
        post directory_exposures_path, params: { app_id: oauth_app.id, entitlement_slug: entitlement.slug, claim_name: "docs" }
      }.not_to change(Directory::Exposure, :count)

      expect {
        post developer_app_session_revoker_path(oauth_app),
          params: { revoker: { adapter: "webhook", enabled: "1", fields: { url: "https://x.example/r", secret: "s" } } }
      }.not_to change(Directory::AppRevoker, :count)
    end

    it "keeps the grants they hold as a person" do
      person = Directory::Person.find_by!(identity: admin)
      group = create(:directory_group, slug: "crew")
      grantee = create(:directory_group)
      Directory.mutate!(cause: "test") do
        Directory::Membership.create!(collection: grantee, member_person: person)
        Directory::Grant.create!(grantee_group: grantee, target_collection: group, permission: "view")
      end

      get directory_collection_path(group.slug)
      expect(response).to have_http_status(:ok)
    end
  end

  context "with 2FA" do
    it "is a directory admin" do
      get directory_root_path
      expect(response).to have_http_status(:ok)

      expect {
        post directory_collections_path, params: { collection: { name: "X", slug: "x-coll", kind: "group" } }
      }.to change(Directory::Collection, :count).by(1)
    end
  end
end
