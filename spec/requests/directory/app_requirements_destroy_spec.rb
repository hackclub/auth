# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Removing an app requirement", type: :request do
  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  let(:admin) { create(:identity) }
  let!(:backend_user) { create(:backend_user, identity: admin, directory_services_admin: true) }
  let(:oauth_app) { create(:program, owner_identity: create(:identity), trust_level: :hq_official) }
  let(:e1) { create(:directory_entitlement, slug: "e1") }
  let(:e2) { create(:directory_entitlement, slug: "e2") }

  let(:holder) { create(:identity) }
  let!(:token) { create(:oauth_token, resource_owner: holder, application: oauth_app) }

  before do
    person = Directory::Person.create!(identity: holder, created_by_identity_id: admin.id)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: e2, member_person: person, created_by_identity_id: admin.id)
    end
    sign_in admin
  end

  def unwire(entitlement) = delete(directory_app_requirement_path(entitlement.slug), params: { app_id: oauth_app.id })

  it "revokes holders who only qualified through the removed entitlement" do
    Directory::AppRequirement.create!(app: oauth_app, entitlement: e1)
    Directory::AppRequirement.create!(app: oauth_app, entitlement: e2)

    unwire(e2)

    expect(Directory::RequirementCheck.passes?(identity: holder, app: oauth_app)).to be(false)
    expect(token.reload.revoked_at).to be_present
  end

  it "revokes nobody when the last requirement goes and the app opens up" do
    Directory::AppRequirement.create!(app: oauth_app, entitlement: e1)

    unwire(e1)

    expect(Directory::AppRequirement.where(app: oauth_app)).to be_empty
    expect(token.reload.revoked_at).to be_nil
  end
end
