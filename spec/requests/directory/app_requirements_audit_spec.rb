# frozen_string_literal: true

require "rails_helper"

RSpec.describe "App requirement audit trail", type: :request do
  let(:admin) do
    create(:identity).tap do |i|
      create(:backend_user, identity: i, directory_services_admin: true, program_manager: true)
      i.reload
    end
  end
  let(:oauth_app) { create(:program, owner_identity: create(:identity), trust_level: :hq_official, name: "Gated App") }
  let(:entitlement) { create(:directory_entitlement, slug: "staff", name: "Staff") }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(admin)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  it "records who added and removed a requirement, on the app and on the entitlement" do
    post directory_app_requirements_path, params: { app_id: oauth_app.id, entitlement_slug: entitlement.slug }
    delete directory_app_requirement_path(entitlement.slug), params: { app_id: oauth_app.id }

    %w[program.requirement_added program.requirement_removed].each do |key|
      expect(PublicActivity::Activity.find_by!(trackable: oauth_app, key: key).owner).to eq(admin)
    end
    %w[directory_collection.requirement_added directory_collection.requirement_removed].each do |key|
      expect(PublicActivity::Activity.find_by!(trackable: entitlement, key: key).owner).to eq(admin)
    end

    get activity_log_developer_app_path(oauth_app)
    expect(response.body).to include("stopped requiring entitlement")

    get directory_activity_path
    expect(response.body).to include("required to log in to")
    expect(response.body).to include("Gated App")
  end
end
