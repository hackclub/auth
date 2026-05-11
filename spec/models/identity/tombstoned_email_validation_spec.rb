# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Identity tombstoned email validation" do
  before { TombstonedEmail.tombstone!("tombstoned@example.com") }

  describe "new identity creation" do
    it "rejects a tombstoned email" do
      identity = build(:identity, primary_email: "tombstoned@example.com")
      expect(identity).not_to be_valid
      expect(identity.errors[:primary_email]).to be_present
    end

    it "rejects case-insensitive match" do
      identity = build(:identity, primary_email: "TOMBSTONED@Example.COM")
      expect(identity).not_to be_valid
      expect(identity.errors[:primary_email]).to be_present
    end

    it "allows a non-tombstoned email" do
      identity = build(:identity, primary_email: "fresh@example.com")
      expect(identity).to be_valid
    end

    it "does not reveal that the email was tombstoned" do
      identity = build(:identity, primary_email: "tombstoned@example.com")
      identity.valid?
      message = identity.errors[:primary_email].join
      expect(message).not_to include("tombstone")
      expect(message).not_to include("deleted")
      expect(message).not_to include("banned")
    end
  end
end
