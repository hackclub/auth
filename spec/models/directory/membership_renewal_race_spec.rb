# frozen_string_literal: true

require "rails_helper"

RSpec.describe Directory::Membership do
  it "clears the sweep's expiry stamp on renewal even when loaded before the sweep ran" do
    group = create(:directory_group)
    person = create(:directory_person)
    Directory.mutate!(cause: "test") do
      described_class.create!(collection: group, member_person: person, expires_at: 1.day.from_now)
    end
    stale = described_class.find_by!(collection: group, member_person: person)

    described_class.where(id: stale.id).update_all(expires_at: 1.minute.ago, expiry_recorded_at: Time.current)

    stale.update!(expires_at: 30.days.from_now)

    expect(stale.reload.expiry_recorded_at).to be_nil
  end
end
