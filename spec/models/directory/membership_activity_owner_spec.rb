# frozen_string_literal: true

require "rails_helper"

RSpec.describe Directory::Membership, "activity owner outside a request" do
  it "credits the adder for an add, but nobody for a removal" do
    adder = create(:identity)
    group = create(:directory_group)
    person = create(:directory_person)
    Directory.mutate!(cause: "test") { described_class.create!(collection: group, member_person: person, created_by_identity_id: adder.id) }
    expect(PublicActivity::Activity.where(key: "directory_collection.member_added").last.owner).to eq(adder)

    Directory.mutate!(cause: "test") { described_class.find_by!(collection: group, member_person: person).destroy! }
    expect(PublicActivity::Activity.where(key: "directory_collection.member_removed").last.owner).to be_nil
  end
end
