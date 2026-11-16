# frozen_string_literal: true

require "rails_helper"

RSpec.describe Directory::ValidateJob do
  it "prunes membership change rows past retention" do
    row = { collection: create(:directory_group), person: create(:directory_person), op: "added", cause: "test" }
    old = Directory::MembershipChange.create!(**row, created_at: 31.days.ago)
    recent = Directory::MembershipChange.create!(**row, created_at: 1.day.ago)
    Directory.mutate!(cause: "test") { }

    described_class.perform_now

    expect(Directory::MembershipChange.exists?(old.id)).to be(false)
    expect(Directory::MembershipChange.exists?(recent.id)).to be(true)
  end

  it "fails the run with a summary when the derived tables drift" do
    person = create(:directory_person)
    group = create(:directory_group)
    Directory.mutate!(cause: "test") { }
    Directory::EffectiveMembership.insert_all([ { person_id: person.id, collection_id: group.id } ])

    expect { described_class.perform_now }.to raise_error(described_class::DriftDetected, /effective_memberships: 0 missing, 1 extra/)
  end

  it "names expiry-only drift in the summary" do
    person = create(:directory_person)
    group = create(:directory_group)
    Directory.mutate!(cause: "test") { Directory::Membership.create!(collection: group, member_person: person) }
    Directory::EffectiveMembership.where(person_id: person.id, collection_id: group.id).update_all(expires_at: 1.day.from_now)

    expect { described_class.perform_now }.to raise_error(described_class::DriftDetected, /effective_memberships: 0 missing, 0 extra, 1 stale expiry/)
  end
end
