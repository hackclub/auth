# frozen_string_literal: true

require "rails_helper"

RSpec.describe Directory::Import, "re-adding expired members" do
  let(:admin) { create(:identity) }
  let(:member_identity) { create(:identity) }
  let!(:group) { create(:directory_group, slug: "team") }

  def import(csv_string, dry_run: false)
    Directory::Import.call(csv_string: csv_string, dry_run: dry_run, created_by: admin)
  end

  def add_and_expire(person)
    membership = nil
    Directory.mutate!(cause: "test") do
      membership = Directory::Membership.create!(
        collection: group, member_person: person,
        expires_at: 1.day.from_now, created_by_identity_id: admin.id
      )
    end
    membership.update_columns(expires_at: 1.hour.ago)
    Directory::Rebuild.call(cause: "test-expire", skip_lock: false)
    membership
  end

  it "re-adds a person whose membership expired instead of skipping them" do
    person = Directory::Person.create!(identity: member_identity, created_by_identity_id: admin.id)
    add_and_expire(person)

    expect(Directory::Membership.active.where(collection: group, member_person: person)).not_to exist

    tomorrow = 1.day.from_now.to_date.iso8601
    result = import("#{member_identity.primary_email},team,#{tomorrow}\n")

    expect(result).to be_valid
    expect(result.created_count).to eq(1)
    expect(result.skipped_count).to eq(0)
    expect(Directory::Membership.active.where(collection: group, member_person: person)).to exist
  end

  it "reports expired members as 'add' in dry_run preview" do
    person = Directory::Person.create!(identity: member_identity, created_by_identity_id: admin.id)
    add_and_expire(person)

    result = import("#{member_identity.primary_email},team,\n", dry_run: true)

    expect(result.changes).to contain_exactly(
      a_hash_including(action: "add", email: member_identity.primary_email.downcase)
    )
  end

  it "still skips active members" do
    person = Directory::Person.create!(identity: member_identity, created_by_identity_id: admin.id)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(
        collection: group, member_person: person,
        created_by_identity_id: admin.id
      )
    end

    result = import("#{member_identity.primary_email},team,\n")

    expect(result.skipped_count).to eq(1)
    expect(result.created_count).to eq(0)
  end
end
