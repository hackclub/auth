# frozen_string_literal: true

require "rails_helper"

RSpec.describe "EmailChangeRequest tombstoned email validation" do
  let(:identity) { create(:identity) }

  before { TombstonedEmail.tombstone!("tombstoned@example.com") }

  it "rejects changing to a tombstoned email" do
    request = build(:email_change_request, identity: identity, new_email: "tombstoned@example.com")
    expect(request).not_to be_valid
    expect(request.errors[:new_email]).to be_present
  end

  it "rejects case-insensitive match" do
    request = build(:email_change_request, identity: identity, new_email: "TOMBSTONED@Example.COM")
    expect(request).not_to be_valid
    expect(request.errors[:new_email]).to be_present
  end

  it "allows a non-tombstoned email" do
    request = build(:email_change_request, identity: identity, new_email: "fresh@example.com")
    expect(request).to be_valid
  end
end
