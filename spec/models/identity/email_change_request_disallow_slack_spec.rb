# frozen_string_literal: true

require "rails_helper"

RSpec.describe "EmailChangeRequest disallow_slack validation" do
  let(:identity) { create(:identity, primary_email: "blocked@example.com") }

  it "rejects a new request from an identity blocked from Slack" do
    identity.update!(disallow_slack: true)

    request = build(:email_change_request, identity: identity, new_email: "fresh@example.com")
    expect(request).not_to be_valid
    expect(request.errors[:base]).to be_present
  end

  it "allows a request from an identity that isn't blocked" do
    request = build(:email_change_request, identity: identity, new_email: "fresh@example.com")
    expect(request).to be_valid
  end

  it "cancels instead of completing if the identity is blocked mid-flight" do
    request = create(:email_change_request, identity: identity, new_email: "fresh@example.com")
    identity.update!(disallow_slack: true)

    request.update!(old_email_verified_at: Time.current, new_email_verified_at: Time.current)
    request.complete_if_ready!

    expect(request.reload).to be_cancelled
    expect(request).not_to be_completed
    expect(identity.reload.primary_email).to eq("blocked@example.com")
  end
end
