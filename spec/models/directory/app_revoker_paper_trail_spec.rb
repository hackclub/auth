# frozen_string_literal: true

require "rails_helper"

RSpec.describe Directory::AppRevoker, "versions" do
  it "never writes the decrypted config to paper_trail" do
    app = create(:program, trust_level: :hq_official)
    revoker = described_class.new(app: app)
    revoker.assign_settings(adapter: "cloudflare_access", fields: { "account_id" => "0123456789abcdef0123456789abcdef", "api_token" => "SUPERSECRETTOKEN" })
    revoker.save!
    revoker.assign_settings(adapter: "cloudflare_access", fields: { "account_id" => "0123456789abcdef0123456789abcdef", "api_token" => "OTHERSECRETTOKEN" })
    revoker.save!

    versions = PaperTrail::Version.where(item_type: described_class.name)
    expect(versions).not_to be_empty
    dump = versions.map { |v| [ v.object, v.object_changes ].to_s }.join
    expect(dump).not_to include("SUPERSECRETTOKEN")
    expect(dump).not_to include("OTHERSECRETTOKEN")
  end
end
