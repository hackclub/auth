# frozen_string_literal: true

require "rails_helper"

RSpec.describe Directory::AfterChangeJob do
  include ActiveJob::TestHelper

  let(:admin) { create(:identity) }
  let(:identity) { create(:identity) }
  let!(:person) { Directory::Person.create!(identity: identity, created_by_identity_id: admin.id) }
  let(:app) { create(:program) }
  let(:staff) { create(:directory_entitlement, slug: "staff") }
  let(:other) { create(:directory_entitlement, slug: "other") }

  def add(collection, who = person)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: collection, member_person: who, created_by_identity_id: admin.id)
    end
  end

  def remove(collection, who = person)
    Directory.mutate!(cause: "test") do
      Directory::Membership.where(collection: collection, member_person: who).destroy_all
    end
  end

  def token = @token ||= create(:oauth_token, resource_owner: identity, application: app)

  context "app that only receives the entitlement as a groups claim" do
    before do
      Directory::Exposure.create!(app: app, entitlement: staff, claim_name: "staff")
      add(staff)
      token
    end

    it "revokes when the person leaves the exposed entitlement" do
      perform_enqueued_jobs { remove(staff) }
      expect(token.reload.revoked_at).to be_present
    end

    it "fires the app's revoker" do
      Directory::AppRevoker.create!(app: app, adapter: "webhook", config: { url: "https://example.com" }.to_json, enabled: true)
      remove(staff)
      expect { perform_enqueued_jobs(only: described_class) }
        .to have_enqueued_job(Directory::RevokeSessionJob).with(app_id: app.id, email: identity.primary_email)
    end

    it "revokes everyone when the entitlement is deleted" do
      revocations = staff.effective_people.map { |p| p.revocation_entry(staff.affected_app_ids) }
      Directory.mutate!(cause: "test") { staff.destroy! }
      described_class.perform_now(change_ids: [], revocations: revocations)
      expect(token.reload.revoked_at).to be_present
    end

    it "leaves the token alone when the person was re-added before the job ran" do
      remove(staff)
      add(staff)
      perform_enqueued_jobs(only: described_class)
      expect(token.reload.revoked_at).to be_nil
    end
  end

  context "app with requirements" do
    before do
      Directory::AppRequirement.create!(app: app, entitlement: staff)
      Directory::AppRequirement.create!(app: app, entitlement: other)
      add(staff)
      add(other)
      token
    end

    it "keeps access while another required entitlement still qualifies" do
      perform_enqueued_jobs { remove(staff) }
      expect(token.reload.revoked_at).to be_nil
    end

    it "revokes once no required entitlement is left" do
      perform_enqueued_jobs do
        remove(staff)
        remove(other)
      end
      expect(token.reload.revoked_at).to be_present
    end
  end

  it "revokes for a lost exposed entitlement even when the person still passes the requirements" do
    Directory::AppRequirement.create!(app: app, entitlement: other)
    Directory::Exposure.create!(app: app, entitlement: staff, claim_name: "staff")
    add(staff)
    add(other)
    token
    perform_enqueued_jobs { remove(staff) }
    expect(token.reload.revoked_at).to be_present
  end
end
