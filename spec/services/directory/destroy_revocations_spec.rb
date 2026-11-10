# frozen_string_literal: true

require "rails_helper"

RSpec.describe Directory::DestroyRevocations do
  let(:app) { create(:program) }
  let(:entitlement) { create(:directory_entitlement) }
  let(:person) { create(:directory_person) }

  before do
    Directory::Exposure.create!(app: app, entitlement: entitlement, claim_name: "staff")
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: entitlement, member_person: person, expires_at: 2.minutes.from_now)
    end
  end

  # lapsed at 10:01, deleted at 10:03 before any sweep: the holder was never revoked
  context "when the membership lapsed but hasn't been swept" do
    before do
      Directory::Membership.update_all(expires_at: 1.minute.ago)
      Directory::EffectiveMembership.unscoped.update_all(expires_at: 1.minute.ago)
    end

    it "still revokes the holder when the entitlement is deleted" do
      expect(Directory::EffectiveMembership.where(person_id: person.id)).to be_empty
      expect(described_class.for_entitlement(entitlement)).to contain_exactly(hash_including(identity_id: person.identity_id, app_ids: [ app.id ]))
    end

    it "still revokes the holder when the person is deleted" do
      expect(described_class.for_person(person)).to contain_exactly(hash_including(identity_id: person.identity_id, app_ids: [ app.id ]))
    end
  end

  it "covers live holders too" do
    expect(described_class.for_entitlement(entitlement).map { |r| r[:identity_id] }).to eq([ person.identity_id ])
  end
end
