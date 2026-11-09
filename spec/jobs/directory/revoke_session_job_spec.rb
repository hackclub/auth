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
end
