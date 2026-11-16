# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Effective grant expiry" do
  let(:person) { create(:directory_person) }
  let(:grantee) { create(:directory_group) }
  let(:target) { create(:directory_group) }
  let(:nested) { create(:directory_group) }
  let(:membership_expiry) { 2.days.from_now.change(usec: 0) }
  let(:nesting_expiry) { 1.day.from_now.change(usec: 0) }

  before do
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: grantee, member_person: person, expires_at: membership_expiry)
      Directory::Membership.create!(collection: target, member_group: nested, expires_at: nesting_expiry)
      Directory::Grant.create!(grantee_group: grantee, target_collection: target, permission: "manage_members", recursive: true)
    end
  end

  def raw_grant(collection)
    ActiveRecord::Base.connection.select_value(<<~SQL)
      SELECT expires_at FROM directory_effective_grants
      WHERE person_id = #{person.id} AND target_collection_id = #{collection.id} AND permission = 'manage_members'
    SQL
  end

  def context = Directory::Context.new(identity: person.identity, person: person, admin: false)

  it "expires each grant with the earliest-lapsing edge on its path" do
    expect(raw_grant(target)).to be_within(1.second).of(membership_expiry)
    expect(raw_grant(nested)).to be_within(1.second).of(nesting_expiry)
  end

  it "stops authorizing once the path has lapsed, before any rebuild" do
    expect(context.can?(:manage_members, nested)).to be(true)

    ActiveRecord::Base.connection.execute(<<~SQL)
      UPDATE directory_effective_grants SET expires_at = NOW() - interval '1 minute'
      WHERE person_id = #{person.id} AND target_collection_id = #{nested.id}
    SQL

    expect(context.can?(:manage_members, nested)).to be(false)
    expect(context.can_any?(%w[manage_members], nested)).to be(false)
    expect(context.preload_grants!.can?(:manage_members, nested)).to be(false)
    expect(context.can?(:manage_members, target)).to be(true)
  end

  it "keeps a grant permanent when any path to it is permanent" do
    Directory.mutate!(cause: "test") do
      other = create(:directory_group)
      Directory::Membership.create!(collection: other, member_person: person)
      Directory::Grant.create!(grantee_group: other, target_collection: target, permission: "manage_members")
    end

    expect(raw_grant(target)).to be_nil
  end
end
