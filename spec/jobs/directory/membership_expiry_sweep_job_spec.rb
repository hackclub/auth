# frozen_string_literal: true

require "rails_helper"

RSpec.describe Directory::MembershipExpirySweepJob do
  let(:admin) { create(:identity) }
  let(:manager) { Directory::Person.create!(identity: create(:identity), created_by_identity_id: admin.id) }
  let(:grantee) { create(:directory_group, slug: "grantee") }
  let(:parent) { create(:directory_group, slug: "parent") }
  let(:child) { create(:directory_group, slug: "child") }

  # child is nested in parent with an expiry and has no people in it; a recursive
  # manage_members grant on parent reaches child only through that edge
  before do
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: grantee, member_person: manager, created_by_identity_id: admin.id)
      Directory::Grant.create!(grantee_group: grantee, target_collection: parent, permission: "manage_members", recursive: true, created_by_identity_id: admin.id)
      Directory::Membership.create!(collection: parent, member_group: child, expires_at: 1.day.from_now, created_by_identity_id: admin.id)
    end
  end

  let(:nesting) { Directory::Membership.find_by!(collection: parent, member_group: child) }

  # the rebuild compares against postgres NOW(), which time travel can't move
  def lapse! = nesting.update_columns(expires_at: 1.minute.ago)

  def expiry_activities = PublicActivity::Activity.where(key: "directory_collection.member_removed")

  it "drops recursive grants through an expired nesting edge nobody is a member through" do
    expect(Directory::EffectiveGrant.where(target_collection_id: child.id)).to exist

    lapse!
    described_class.perform_now

    expect(Directory::EffectiveGrant.where(target_collection_id: child.id)).not_to exist
    expect(Directory::Validate.call).to be_valid
  end

  it "records each expiry once, with an activity and a paper_trail version" do
    lapse!

    expect { described_class.perform_now }
      .to change { expiry_activities.count }.by(1)
      .and change { nesting.versions.count }.by(1)

    expect(expiry_activities.last.parameters).to include(reason: "expired", member_name: child.name)
    expect(nesting.reload.expiry_recorded_at).to be_present

    # nothing new to sweep, so no second rebuild or activity
    expect(Directory).not_to receive(:mutate!)
    described_class.perform_now
  end

  it "doesn't log a second expiry when the swept row is purged on re-add" do
    lapse!
    described_class.perform_now

    expect {
      Directory::Membership.purge_expired!(Directory::Membership.where(id: nesting.id))
    }.not_to change { PublicActivity::Activity.count }
    expect(Directory::Membership.exists?(nesting.id)).to be(false)
    expect(PaperTrail::Version.where(item_type: "Directory::Membership", item_id: nesting.id, event: "destroy")).to exist
  end

  it "says 'expired' when a lapsed row is purged before the sweep got to it" do
    lapse!

    expect {
      Directory::Membership.purge_expired!(Directory::Membership.where(id: nesting.id))
    }.to change { expiry_activities.count }.by(1)
    expect(expiry_activities.last.parameters).to include(reason: "expired")
  end
end
