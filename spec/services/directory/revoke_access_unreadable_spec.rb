# frozen_string_literal: true

require "rails_helper"

RSpec.describe Directory::RevokeAccess, ".revoke_sessions with an unreadable revoker" do
  include ActiveJob::TestHelper

  let(:broken_app) { create(:program) }
  let(:fine_app) { create(:program) }

  before do
    Directory::AppRevoker.new(app: broken_app, adapter: "cloudflare_access", config: { account_id: "a" * 32, api_token: "t" }.to_json).tap { |r| r.save!(validate: false) }
      .update_columns(config_ciphertext: "not-a-ciphertext")
    Directory::AppRevoker.create!(app: fine_app, adapter: "webhook", config: { url: "https://b.example/r" }.to_json)
    allow(Sentry).to receive(:capture_exception)
  end

  it "still enqueues every app's revocation and reports the broken one" do
    expect {
      described_class.revoke_sessions([ [ broken_app.id, "p@example.com" ], [ fine_app.id, "p@example.com" ] ])
    }.to have_enqueued_job(Directory::RevokeSessionJob).exactly(2).times

    expect(Sentry).to have_received(:capture_exception).with(kind_of(Lockbox::Error), extra: { app_id: broken_app.id })
  end
end
