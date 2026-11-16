# frozen_string_literal: true

require "rails_helper"

RSpec.describe Identity, "#lock_account!", type: :model do
  include ActiveJob::TestHelper

  let(:identity) { create(:identity) }
  let(:app) { create(:program, :with_groups) }
  let(:staff) { create(:directory_entitlement) }

  it "fires the revoker of every app the identity reaches through the directory" do
    person = create(:directory_person, identity: identity)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: staff, member_person: person, created_by_identity_id: identity.id)
    end
    Directory::Exposure.create!(app: app, entitlement: staff, claim_name: "staff")
    Directory::AppRevoker.create!(app: app, adapter: "webhook", config: { url: "https://example.com" }.to_json, enabled: true)

    expect { identity.lock_account! }
      .to have_enqueued_job(Directory::RevokeSessionJob).with(app_id: app.id, email: identity.primary_email, fallback_app_ids: [])
  end

  it "fires the revoker of an app they signed in to, wired or not" do
    open_app = create(:program)
    Directory::AppRevoker.create!(app: open_app, adapter: "webhook", config: { url: "https://example.com" }.to_json, enabled: true)
    create(:oauth_token, resource_owner: identity, application: open_app)

    expect { identity.lock_account! }
      .to have_enqueued_job(Directory::RevokeSessionJob).with(app_id: open_app.id, email: identity.primary_email, fallback_app_ids: [])
  end

  it "doesn't call revokers for apps they never used" do
    expect { identity.lock_account! }.not_to have_enqueued_job(Directory::RevokeSessionJob)
    expect(identity.reload.locked_at).to be_present
  end
end
