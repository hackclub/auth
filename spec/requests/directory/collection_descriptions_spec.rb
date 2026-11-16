# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Collection descriptions", type: :request do
  DESCRIPTION = "apps accessible to people employed full-time by Hack Club HQ"

  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  let!(:entitlement) { create(:directory_entitlement, slug: "hq-fulltimers-apps", description: DESCRIPTION) }

  it "shows on the collections index" do
    admin = create(:identity)
    create(:backend_user, identity: admin, directory_services_admin: true)
    sign_in admin.reload

    get directory_root_path
    expect(response.body).to include(DESCRIPTION)
  end

  it "shows on my access for things the person can see, and not for things they can't" do
    person = create(:directory_person)
    hidden = create(:directory_entitlement, slug: "secret-thing", description: "the hidden one")
    grantee = create(:directory_group)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: entitlement, member_person: person)
      Directory::Membership.create!(collection: hidden, member_person: person)
      Directory::Membership.create!(collection: grantee, member_person: person)
      Directory::Grant.create!(grantee_group: grantee, target_collection: entitlement, permission: "view")
    end
    sign_in person.identity

    get directory_my_access_path
    expect(response.body).to include(DESCRIPTION)
    expect(response.body).not_to include("the hidden one")
  end
end
