# frozen_string_literal: true

require "rails_helper"

RSpec.describe Directory::AfterChangeJob do
  include ActiveJob::TestHelper

  let(:admin) { create(:identity) }
  let(:identity) { create(:identity) }
  let!(:person) { Directory::Person.create!(identity: identity, created_by_identity_id: admin.id) }
  let(:app) { create(:program, :with_groups) }
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

  context "app that stopped requesting groups" do
    before do
      Directory::Exposure.create!(app: app, entitlement: staff, claim_name: "staff")
      add(staff)
    end

    it "still revokes a person whose token was issued with the groups claim" do
      groups_token = create(:oauth_token, resource_owner: identity, application: app, scopes: "basic_info groups")
      app.update_columns(scopes: "basic_info email name")

      perform_enqueued_jobs { remove(staff) }

      expect(groups_token.reload.revoked_at).to be_present
    end

    it "leaves a person alone whose tokens never carried the claim" do
      plain = create(:oauth_token, resource_owner: identity, application: app, scopes: "basic_info")
      app.update_columns(scopes: "basic_info email name")

      perform_enqueued_jobs { remove(staff) }
      expect(plain.reload.revoked_at).to be_nil

      expect(Directory::DestroyRevocations.for_entitlement(staff)).to be_empty
    end
  end

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
        .to have_enqueued_job(Directory::RevokeSessionJob).with(app_id: app.id, email: identity.primary_email, fallback_app_ids: [])
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

  context "a whole group losing an entitlement" do
    let(:team) { create(:directory_group, slug: "team") }
    let(:app2) { create(:program, :with_groups) }
    let(:members) { Array.new(4) { create(:identity) } }

    def cf_revoker(for_app, account)
      Directory::AppRevoker.create!(app: for_app, adapter: "cloudflare_access", enabled: true,
        config: { account_id: account, api_token: "t" }.to_json)
    end

    before do
      [ app, app2 ].each { |a| Directory::Exposure.create!(app: a, entitlement: staff, claim_name: "staff") }
      members.each do |m|
        add(team, Directory::Person.create!(identity: m, created_by_identity_id: admin.id))
        create(:oauth_token, resource_owner: m, application: app)
        create(:oauth_token, resource_owner: m, application: app2)
      end
      Directory.mutate!(cause: "test") do
        Directory::Membership.create!(collection: staff, member_group: team, created_by_identity_id: admin.id)
      end
    end

    def cut_team_from_staff
      Directory.mutate!(cause: "test") { Directory::Membership.where(collection: staff, member_group: team).destroy_all }
    end

    def queries_for_cut
      cut_team_from_staff
      queries = 0
      counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        perform_enqueued_jobs(only: described_class)
      end
      queries
    end

    it "revokes every member's tokens" do
      queries_for_cut
      expect(OAuthToken.where(resource_owner_id: members.map(&:id), revoked_at: nil)).to be_empty
    end

    it "doesn't query per member" do
      small = queries_for_cut

      more = Array.new(8) { create(:identity) }
      more.each do |m|
        add(team, Directory::Person.create!(identity: m, created_by_identity_id: admin.id))
        create(:oauth_token, resource_owner: m, application: app)
      end
      Directory.mutate!(cause: "test") do
        Directory::Membership.create!(collection: staff, member_group: team, created_by_identity_id: admin.id)
      end
      perform_enqueued_jobs(only: described_class)

      expect(queries_for_cut).to be <= small
    end

    it "makes one revoke call per person for apps on the same cloudflare account" do
      cf_revoker(app, "0123456789abcdef0123456789abcdef")
      cf_revoker(app2, "0123456789abcdef0123456789abcdef")
      cut_team_from_staff

      perform_enqueued_jobs(only: described_class)

      revoke_jobs = enqueued_jobs.select { |j| j["job_class"] == "Directory::RevokeSessionJob" }
      expect(revoke_jobs.size).to eq(members.size)
    end

    it "keeps separate calls for different accounts" do
      cf_revoker(app, "0123456789abcdef0123456789abcdef")
      cf_revoker(app2, "fedcba9876543210fedcba9876543210")
      cut_team_from_staff

      perform_enqueued_jobs(only: described_class)

      expect(enqueued_jobs.count { |j| j["job_class"] == "Directory::RevokeSessionJob" }).to eq(members.size * 2)
    end
  end

  it "retries instead of dropping the revocations when something transient fails" do
    revocations = [ { identity_id: identity.id, email: identity.primary_email, app_ids: [ app.id ] } ]
    allow(Directory::RevokeAccess).to receive(:revoke_tokens).and_raise(ActiveRecord::Deadlocked)

    expect { described_class.perform_now(change_ids: [], revocations: revocations) }
      .to have_enqueued_job(described_class).with(change_ids: [], revocations: revocations)
  end

  it "ignores exposures on apps that never asked for the groups claim" do
    plain = create(:program)
    Directory::Exposure.new(app: plain, entitlement: staff, claim_name: "staff").save!(validate: false)
    add(staff)
    plain_token = create(:oauth_token, resource_owner: identity, application: plain)

    perform_enqueued_jobs { remove(staff) }

    expect(plain_token.reload.revoked_at).to be_nil
  end
end
