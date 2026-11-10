# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe Directory::RevokeSessionJob do
  include ActiveJob::TestHelper

  let(:app) { create(:program) }
  let!(:revoker) do
    Directory::AppRevoker.create!(app: app, adapter: "webhook", enabled: true, config: { url: "https://hooks.example.test/revoke" }.to_json)
  end

  it "reports to Sentry once retries run out, without the email" do
    stub_request(:post, "https://hooks.example.test/revoke").to_return(status: 503)
    allow(Sentry).to receive(:capture_exception)

    perform_enqueued_jobs { described_class.perform_later(app_id: app.id, email: "gone@example.test") }

    expect(a_request(:post, "https://hooks.example.test/revoke")).to have_been_made.times(10)
    expect(Sentry).to have_received(:capture_exception)
      .with(instance_of(described_class::RevocationFailed), extra: { app_id: app.id }).once
    expect(revoker.reload.last_result).to start_with("failed")
  end

  it "throttles per cloudflare account, not per app" do
    other = create(:program)
    cf = ->(a) { Directory::AppRevoker.create!(app: a, adapter: "cloudflare_access", enabled: true, config: { account_id: "acct", api_token: "t" }.to_json) }
    cf.(other)
    revoker.update!(adapter: "cloudflare_access", config: { account_id: "acct", api_token: "t" }.to_json)

    keys = [ app, other ].map { |a| described_class.new(app_id: a.id, email: "x@example.test").good_job_concurrency_key }
    expect(keys.uniq).to eq([ "directory-revoke:cloudflare_access:acct" ])
  end

  context "with several apps on one cloudflare account" do
    let(:other) { create(:program) }
    let(:url) { "https://api.cloudflare.com/client/v4/accounts/acct/access/organizations/revoke_user" }

    before do
      revoker.update!(adapter: "cloudflare_access", config: { account_id: "acct", api_token: "expired" }.to_json)
      Directory::AppRevoker.create!(app: other, adapter: "cloudflare_access", enabled: true, config: { account_id: "acct", api_token: "good" }.to_json)
      stub_request(:post, url).with(headers: { "Authorization" => "Bearer expired" }).to_return(status: 403)
      stub_request(:post, url).with(headers: { "Authorization" => "Bearer good" }).to_return(status: 200)
    end

    it "makes one call per person and falls back to a working revoker in the same scope" do
      Directory::RevokeAccess.revoke_sessions([ [ app.id, "p@example.test" ], [ other.id, "P@example.test" ] ])

      expect(enqueued_jobs.size).to eq(1)
      perform_enqueued_jobs

      expect(a_request(:post, url).with(headers: { "Authorization" => "Bearer good" })).to have_been_made.once
      expect(revoker.reload.last_result).to start_with("failed")
      expect(enqueued_jobs).to be_empty
    end

    it "falls back when the first app's revoker is disabled" do
      revoker.update!(enabled: false)

      described_class.perform_now(app_id: app.id, email: "p@example.test", fallback_app_ids: [ other.id ])

      expect(a_request(:post, url).with(headers: { "Authorization" => "Bearer good" })).to have_been_made.once
    end
  end
end
