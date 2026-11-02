# frozen_string_literal: true

require "rails_helper"

RSpec.describe Directory::Collection, "#recursive_grant_reach", type: :model do
  def nest!(child, under:)
    create(:directory_membership, collection: under, member_group: child)
  end

  # x ─┬─ a ── a1
  #    ├─ b ── a             (diamond: a is reachable twice)
  #    └─ p (protected) ── p1
  let(:x)  { create(:directory_group, slug: "x") }
  let(:a)  { create(:directory_group, slug: "a") }
  let(:a1) { create(:directory_group, slug: "a1") }
  let(:b)  { create(:directory_group, slug: "b") }
  let(:p)  { create(:directory_group, slug: "p", protected: true) }
  let(:p1) { create(:directory_group, slug: "p1") }

  before do
    nest!(a, under: x)
    nest!(a1, under: a)
    nest!(b, under: x)
    nest!(a, under: b)
    nest!(p, under: x)
    nest!(p1, under: p)
  end

  it "is the collection and its sub-groups, never entering a protected one" do
    expect(x.recursive_grant_reach).to contain_exactly(x, a, a1, b)
  end

  it "is empty for a protected collection, since recursion can't enter it" do
    expect(p.recursive_grant_reach).to be_empty
  end

  it "covers exactly what a recursive grant flowing into the collection reaches after a rebuild" do
    parent = create(:directory_group, slug: "parent")
    nest!(x, under: parent)
    person = create(:directory_person)
    grantee = create(:directory_group, slug: "grantee")
    create(:directory_membership, collection: grantee, member_person: person)
    create(:directory_grant, grantee_group: grantee, target_collection: parent, permission: "view", recursive: true)

    Directory::Rebuild.call(cause: "test")

    reached = Directory::EffectiveGrant.where(person: person).pluck(:target_collection_id) - [ parent.id ]
    expect(reached).to match_array(x.recursive_grant_reach.ids)
  end

  it "stops MAX_DEPTH levels down, like the grant expansion" do
    chain = [ x ]
    (Directory::MAX_DEPTH + 1).times do |i|
      child = create(:directory_group, slug: "deep-#{i}")
      # deeper than membership validation allows; the walk must still terminate at the bound
      Directory::Membership.new(collection: chain.last, member_group: child).save!(validate: false)
      chain << child
    end

    reach = x.recursive_grant_reach
    expect(reach).to include(chain[Directory::MAX_DEPTH])
    expect(reach).not_to include(chain[Directory::MAX_DEPTH + 1])
  end
end
