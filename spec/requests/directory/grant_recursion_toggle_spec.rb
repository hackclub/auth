# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Directory grant recursion toggle", type: :request do
  let(:admin) { create(:identity) }

  before do
    create(:backend_user, identity: admin, directory_services_admin: true)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(admin.reload)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  it "refuses to make a grant on an entitlement recursive, with a flash" do
    entitlement = create(:directory_entitlement)
    grantee = create(:directory_group)
    Directory.mutate!(cause: "test") do
      Directory::Grant.create!(grantee_group: grantee, target_collection: entitlement, permission: "view")
    end
    grant = Directory::Grant.find_by!(grantee_group: grantee)

    patch directory_collection_grant_path(entitlement.slug, grant), params: { recursive: "1" }

    expect(response).to redirect_to(directory_collection_path(entitlement.slug))
    expect(flash[:alert]).to include("must be a group")
    expect(grant.reload.recursive).to be(false)
  end

  it "doesn't offer 'make recursive' on an entitlement's grants" do
    entitlement = create(:directory_entitlement)
    grantee = create(:directory_group)
    Directory.mutate!(cause: "test") do
      Directory::Grant.create!(grantee_group: grantee, target_collection: entitlement, permission: "view")
    end

    get directory_collection_path(entitlement.slug)

    expect(response.body).not_to include(I18n.t("directory.collections.show.make_recursive"))
  end
end
