# frozen_string_literal: true

require "rails_helper"
require_relative "../../support/saml_test_helpers"

RSpec.describe "Directory activity owners", type: :request do
  include SAMLTestHelpers

  let(:admin) { create(:identity) }

  before do
    create(:backend_user, identity: admin, directory_services_admin: true)
    admin.reload
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(admin)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  def last_activity(key)
    PublicActivity::Activity.where(key: key).order(:id).last
  end

  it "records who created and deleted a collection" do
    post directory_collections_path, params: { collection: { name: "Owned", slug: "owned", kind: "group" } }
    expect(last_activity("directory_collection.create").owner).to eq(admin)

    delete directory_collection_path("owned")
    expect(last_activity("directory_collection.destroy").owner).to eq(admin)
  end

  it "still names a deleted collection in its membership activity" do
    post directory_collections_path, params: { collection: { name: "Short Lived", slug: "short-lived", kind: "group" } }
    collection = Directory::Collection.find_by!(slug: "short-lived")
    member = create(:identity, first_name: "Mem", last_name: "Ber")
    add_member!(collection, identity: member)

    delete directory_collection_path("short-lived")
    get directory_activity_path

    expect(response.body).to include("Short Lived")
    expect(response.body).not_to include("(deleted)")
  end

  it "records who created and changed a grant" do
    target = create(:directory_group)
    grantee = create(:directory_group)

    post directory_collection_grants_path(target.slug), params: { grantee_group_slug: grantee.slug, permission: "manage_members" }
    expect(last_activity("directory_grant.create").owner).to eq(admin)

    grant = Directory::Grant.find_by!(grantee_group: grantee, target_collection: target)
    patch directory_collection_grant_path(target.slug, grant), params: { recursive: "1" }
    expect(last_activity("directory_grant.update").owner).to eq(admin)
  end

  it "records who added a person to the directory" do
    identity = create(:identity)

    post directory_people_path, params: { identity_id: identity.id }
    expect(last_activity("directory_person.create").owner).to eq(admin)
  end
end
