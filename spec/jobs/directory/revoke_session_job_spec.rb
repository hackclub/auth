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
    cf = ->(a) { Directory::AppRevoker.create!(app: a, adapter: "cloudflare_access", enabled: true, config: { account_id: "0123456789abcdef0123456789abcdef", api_token: "t" }.to_json) }
    cf.(other)
    revoker.update!(adapter: "cloudflare_access", config: { account_id: "0123456789abcdef0123456789abcdef", api_token: "t" }.to_json)

    keys = [ app, other ].map { |a| described_class.new(app_id: a.id, email: "x@example.test").good_job_concurrency_key }
    expect(keys.uniq).to eq([ "directory-revoke:cloudflare_access:0123456789abcdef0123456789abcdef" ])
  end

  context "with several apps on one cloudflare account" do
    let(:other) { create(:program) }
    let(:url) { "https://api.cloudflare.com/client/v4/accounts/0123456789abcdef0123456789abcdef/access/organizations/revoke_user" }

    before do
      revoker.update!(adapter: "cloudflare_access", config: { account_id: "0123456789abcdef0123456789abcdef", api_token: "expired" }.to_json)
      Directory::AppRevoker.create!(app: other, adapter: "cloudflare_access", enabled: true, config: { account_id: "0123456789abcdef0123456789abcdef", api_token: "good" }.to_json)
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

    it "retries when the primary failed transiently, even if the fallback is broken outright" do
      other_revoker = Directory::AppRevoker.find(other.id)
      other_revoker.update_columns(config_ciphertext: "not-a-ciphertext")
      stub_request(:post, url).with(headers: { "Authorization" => "Bearer expired" }).to_return(status: 503)
      allow(Sentry).to receive(:capture_exception)

      expect { described_class.perform_now(app_id: app.id, email: "p@example.test", fallback_app_ids: [ other.id ]) }
        .to have_enqueued_job(described_class)
      expect(Sentry).to have_received(:capture_exception).with(kind_of(Lockbox::Error), extra: { app_id: app.id })
    end

    it "falls back when the first app's revoker is disabled" do
      revoker.update!(enabled: false)

      described_class.perform_now(app_id: app.id, email: "p@example.test", fallback_app_ids: [ other.id ])

      expect(a_request(:post, url).with(headers: { "Authorization" => "Bearer good" })).to have_been_made.once
    end
  end

  it "retries a TLS failure instead of calling it a config error" do
    stub_request(:post, "https://hooks.example.test/revoke").to_raise(OpenSSL::SSL::SSLError.new("SSL_connect returned=1 errno=0 state=error: unexpected eof"))

    expect { described_class.perform_now(app_id: app.id, email: "p@example.test") }
      .to have_enqueued_job(described_class)
    expect(revoker.reload.last_result).to start_with("failed")
  end

  it "keeps only an excerpt of a huge error body" do
    stub_request(:post, "https://hooks.example.test/revoke").to_return(status: 500, body: "x" * 2_000_000)

    expect { described_class.perform_now(app_id: app.id, email: "p@example.test") }.to have_enqueued_job(described_class)
    expect(revoker.reload.last_result.length).to be <= 500
  end

  it "won't call a webhook whose host now resolves to a private address" do
    allow(Directory::AppRevoker).to receive(:internal_host?).and_return(true)
    allow(Sentry).to receive(:capture_exception)

    expect { described_class.perform_now(app_id: app.id, email: "p@example.test") }.to raise_error(ArgumentError)
    expect(a_request(:post, "https://hooks.example.test/revoke")).not_to have_been_made
    expect(revoker.reload.last_result).to start_with("config_error")
  end
end
