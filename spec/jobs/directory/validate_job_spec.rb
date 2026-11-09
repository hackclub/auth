# frozen_string_literal: true

require "rails_helper"

RSpec.describe Directory::ValidateJob do
  it "prunes membership change rows past retention" do
    row = { collection: create(:directory_group), person: create(:directory_person), op: "added", cause: "test" }
    old = Directory::MembershipChange.create!(**row, created_at: 31.days.ago)
    recent = Directory::MembershipChange.create!(**row, created_at: 1.day.ago)

    described_class.perform_now

    expect(Directory::MembershipChange.exists?(old.id)).to be(false)
    expect(Directory::MembershipChange.exists?(recent.id)).to be(true)
  end
end
