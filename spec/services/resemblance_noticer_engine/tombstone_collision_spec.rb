# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ResemblanceNoticerEngine tombstone collision detection" do
  let(:identity) { create(:identity, first_name: "John", last_name: "Smith", birthday: Date.new(2005, 6, 15)) }

  it "creates a TombstoneCollision when name combos overlap" do
    hashes = Deletion.name_combo_hashes("John Smith", Date.new(2005, 6, 15))
    Deletion.create!(email_hash: "deadbeef", name_combos: hashes, privacy_request_reference: "recASDASDASD")

    expect {
      ResemblanceNoticerEngine.run(identity)
    }.to change { identity.tombstone_collisions.count }.by(1)

    collision = identity.tombstone_collisions.last
    expect(collision.deletion.privacy_request_reference).to eq("recASDASDASD")
  end

  it "does not create duplicate collisions on re-run" do
    hashes = Deletion.name_combo_hashes("John Smith", Date.new(2005, 6, 15))
    Deletion.create!(email_hash: "deadbeef", name_combos: hashes)

    ResemblanceNoticerEngine.run(identity)
    expect {
      ResemblanceNoticerEngine.run(identity)
    }.not_to change { identity.tombstone_collisions.count }
  end

  it "does not create collisions when no tombstones match" do
    expect {
      ResemblanceNoticerEngine.run(identity)
    }.not_to change { Identity::TombstoneCollision.count }
  end

  it "matches on partial name overlap (shared token pair)" do
    hashes = Deletion.name_combo_hashes("John Michael Smith", Date.new(2005, 6, 15))
    deletion = Deletion.create!(email_hash: "deadbeef", name_combos: hashes)

    ResemblanceNoticerEngine.run(identity)

    expect(identity.tombstone_collisions.map(&:deletion)).to include(deletion)
  end

  it "does not match when DOB differs" do
    hashes = Deletion.name_combo_hashes("John Smith", Date.new(2000, 1, 1))
    Deletion.create!(email_hash: "deadbeef", name_combos: hashes)

    expect {
      ResemblanceNoticerEngine.run(identity)
    }.not_to change { Identity::TombstoneCollision.count }
  end
end
