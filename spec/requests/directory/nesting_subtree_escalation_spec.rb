# frozen_string_literal: true

require "rails_helper"

# Nesting group X under group G carries every recursive grant that reaches G down into X
# and X's unprotected sub-groups. A non-admin must already manage all of those, or they
# could nest a group they manage under one they hold a recursive grant on and pick up
# manage_members on whatever sits below it.
RSpec.describe "Directory nesting subtree escalation", type: :request do
  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  def grant!(person, collection, permission, recursive: false)
    grantee = create(:directory_group)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: grantee, member_person: person, created_by_identity_id: person.identity_id)
      Directory::Grant.create!(grantee_group: grantee, target_collection: collection, permission: permission,
                               recursive: recursive, created_by_identity_id: person.identity_id)
    end
  end

  def nest!(child, under:)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: under, member_group: child)
    end
  end

  def nest_via_request(child, under:, param: :group_slug)
    value = param == :group_slug ? child.slug : child.id
    post directory_collection_memberships_path(under.slug), params: { param => value }
  end

  def nested?(child, under:)
    Directory::Membership.where(collection: under, member_group: child).exists?
  end

  def manages?(person, collection)
    Directory::EffectiveGrant.where(person: person, target_collection: collection, permission: "manage_members").exists?
  end

  let(:actor) { create(:directory_person) }
  let(:events) { create(:directory_group, slug: "events", name: "Events") }
  let(:hq) { create(:directory_group, slug: "hq", name: "HQ") }
  let(:hq_finance) { create(:directory_group, slug: "hq-finance", name: "HQ Finance") }

  # actor: recursive manage_members on events, plain manage_members on hq.
  # hq-finance sits (unprotected) inside hq, and actor has no grant on it.
  before do
    nest!(hq_finance, under: hq)
    grant!(actor, events, "manage_members", recursive: true)
    grant!(actor, hq, "manage_members")
    sign_in actor.identity
  end

  %i[group_slug member_group_id].each do |param|
    it "refuses nesting a group whose unprotected sub-group the actor can't manage (#{param})" do
      expect { nest_via_request(hq, under: events, param: param) }.not_to change(Directory::EffectiveGrant, :count)

      expect(response).to redirect_to(directory_collection_path(events.slug))
      expect(flash[:alert]).to eq(I18n.t!("directory.flash.need_manage_on_child_subgroups"))
      expect(nested?(hq, under: events)).to be(false)
      expect(manages?(actor, hq_finance)).to be(false)
    end
  end

  it "walks the whole subtree, not just direct children" do
    hq_payroll = create(:directory_group, slug: "hq-payroll")
    nest!(hq_payroll, under: hq_finance)
    grant!(actor, hq_finance, "manage_members")

    nest_via_request(hq, under: events)

    expect(flash[:alert]).to eq(I18n.t!("directory.flash.need_manage_on_child_subgroups"))
    expect(nested?(hq, under: events)).to be(false)
    expect(manages?(actor, hq_payroll)).to be(false)
  end

  it "allows it when the actor already manages the whole subtree" do
    grant!(actor, hq_finance, "manage_members")

    nest_via_request(hq, under: events)

    expect(response).to redirect_to(directory_collection_path(events.slug))
    expect(flash[:notice]).to eq(I18n.t!("directory.flash.member_added"))
    expect(nested?(hq, under: events)).to be(true)
  end

  it "allows it when the unmanaged sub-group is protected, and the grant stops there" do
    hq_finance.update!(protected: true)

    nest_via_request(hq, under: events)

    expect(nested?(hq, under: events)).to be(true)
    expect(manages?(actor, hq_finance)).to be(false)
  end

  it "doesn't walk below a protected sub-group" do
    hq_payroll = create(:directory_group, slug: "hq-payroll")
    nest!(hq_payroll, under: hq_finance)
    hq_finance.update!(protected: true)

    nest_via_request(hq, under: events)

    expect(nested?(hq, under: events)).to be(true)
    expect(manages?(actor, hq_payroll)).to be(false)
  end

  it "only checks the child itself when the child is protected" do
    hq.update!(protected: true)

    nest_via_request(hq, under: events)

    expect(nested?(hq, under: events)).to be(true)
    expect(manages?(actor, hq_finance)).to be(false)
  end

  it "still nests a leaf group the actor manages" do
    leaf = create(:directory_group, slug: "leaf")
    grant!(actor, leaf, "manage_members")

    nest_via_request(leaf, under: events)

    expect(flash[:notice]).to eq(I18n.t!("directory.flash.member_added"))
    expect(nested?(leaf, under: events)).to be(true)
  end

  it "still refuses a child the actor can't manage at all" do
    stranger = create(:directory_group, slug: "stranger")

    nest_via_request(stranger, under: events)

    expect(flash[:alert]).to eq(I18n.t!("directory.flash.need_manage_on_child_group"))
    expect(nested?(stranger, under: events)).to be(false)
  end
end
