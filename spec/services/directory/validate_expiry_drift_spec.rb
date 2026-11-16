# frozen_string_literal: true

require "rails_helper"

RSpec.describe Directory::Validate do
  it "reports an effective row whose expires_at doesn't match the graph" do
    group = create(:directory_group)
    person = create(:directory_person)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: group, member_person: person, expires_at: 10.days.from_now)
    end
    expect(described_class.call).to be_valid

    Directory::EffectiveMembership.where(person_id: person.id).update_all(expires_at: 1.year.from_now)
    result = described_class.call

    expect(result).not_to be_valid
    expect(result.mismatches["directory_effective_memberships"][:stale].size).to eq(1)
  end
end
