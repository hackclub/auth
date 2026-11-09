# frozen_string_literal: true

require "rails_helper"

RSpec.describe Directory::Validate do
  let(:person) { create(:directory_person) }
  let(:group) { create(:directory_group) }
  let(:parent) { create(:directory_group) }

  before do
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: parent, member_group: group, expires_at: 1.day.from_now)
      Directory::Membership.create!(collection: group, member_person: person, expires_at: 1.day.from_now)
    end
  end

  def lapse_all!
    Directory::Membership.update_all(expires_at: 1.minute.ago)
  end

  it "doesn't report a lapsed-but-unswept membership as drift" do
    lapse_all!
    expect(described_class.call).to be_valid
  end

  it "is still valid once the sweep has run" do
    lapse_all!
    Directory::MembershipExpirySweepJob.perform_now
    expect(described_class.call).to be_valid
  end

  it "is still valid when some other rebuild dropped the lapsed rows before the sweep" do
    lapse_all!
    Directory::Rebuild.call(cause: "test")
    expect(described_class.call).to be_valid
  end

  it "still reports real drift" do
    Directory::EffectiveMembership.where(person_id: person.id).delete_all
    result = described_class.call
    expect(result).not_to be_valid
    expect(result.mismatches["directory_effective_memberships"][:missing]).not_to be_empty
  end

  it "still reports extra rows nothing explains" do
    stranger = create(:directory_person)
    Directory::EffectiveMembership.insert_all!([ { person_id: stranger.id, collection_id: group.id } ])
    expect(described_class.call.mismatches["directory_effective_memberships"][:extra]).not_to be_empty
  end
end
