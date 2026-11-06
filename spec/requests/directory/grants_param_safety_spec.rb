# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Grants parameter safety", type: :request do
  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  let(:admin) { create(:identity) }
  let(:group) { create(:directory_group, slug: "team") }

  before do
    create(:backend_user, identity: admin, directory_services_admin: true)
    sign_in admin.reload
  end

  it "returns a redirect (not 500) when grantee_group_slug is absent" do
    post directory_collection_grants_path(group.slug), params: { permission: "view" }

    expect(response.status).to be_in([302, 404])
    expect(response.status).not_to eq(500)
  end

  it "returns a redirect when grantee_group_slug is empty" do
    post directory_collection_grants_path(group.slug), params: { grantee_group_slug: "", permission: "view" }

    expect(response.status).to be_in([302, 404])
  end
end
