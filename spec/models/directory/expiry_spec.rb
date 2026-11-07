# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Directory membership expiry", type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:admin_identity) { create(:identity) }

  before do
    admin_identity.create_backend_user!(directory_services_admin: true)
  end

  def make_person(name: "test")
    identity = create(:identity, first_name: name)
    person = Directory::Person.create!(identity: identity, created_by_identity_id: admin_identity.id)
    [ identity, person ]
  end

  def make_group(slug)
    Directory::Collection.create!(kind: "group", slug: slug, name: slug)
  end

  def make_entitlement(slug)
    Directory::Collection.create!(kind: "entitlement", slug: slug, name: slug)
  end

  def add_person(collection, person, expires_at: nil)
    membership = nil
    Directory.mutate!(cause: "test") do
      membership = Directory::Membership.create!(
        collection: collection, member_person: person,
        expires_at: expires_at, created_by_identity_id: admin_identity.id
      )
    end
    membership
  end

  def add_person_expired(collection, person, expired_at: 1.hour.ago)
    membership = nil
    Directory.mutate!(cause: "test") do
      membership = Directory::Membership.new(
        collection: collection, member_person: person,
        expires_at: expired_at, created_by_identity_id: admin_identity.id
      )
      membership.save!(validate: false)
    end
    membership
  end

  def nest_group(parent, child, expires_at: nil)
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(
        collection: parent, member_group: child,
        expires_at: expires_at, created_by_identity_id: admin_identity.id
      )
    end
  end

  def nest_group_expired(parent, child, expired_at: 1.hour.ago)
    Directory.mutate!(cause: "test") do
      m = Directory::Membership.new(
        collection: parent, member_group: child,
        expires_at: expired_at, created_by_identity_id: admin_identity.id
      )
      m.save!(validate: false)
    end
  end

  describe "direct membership expiry" do
    it "excludes expired memberships from effective_memberships" do
      entitlement = make_entitlement("ent-a")
      _, person = make_person

      add_person_expired(entitlement, person)

      expect(Directory::EffectiveMembership.where(person_id: person.id, collection_id: entitlement.id)).not_to exist
    end

    it "includes active memberships in effective_memberships" do
      entitlement = make_entitlement("ent-b")
      _, person = make_person

      add_person(entitlement, person, expires_at: 1.day.from_now)

      expect(Directory::EffectiveMembership.where(person_id: person.id, collection_id: entitlement.id)).to exist
    end

    it "includes never-expiring memberships in effective_memberships" do
      entitlement = make_entitlement("ent-c")
      _, person = make_person

      add_person(entitlement, person)

      expect(Directory::EffectiveMembership.where(person_id: person.id, collection_id: entitlement.id)).to exist
    end

    it "carries expires_at through to effective_memberships" do
      entitlement = make_entitlement("ent-d")
      _, person = make_person
      tomorrow = 1.day.from_now.change(usec: 0)

      add_person(entitlement, person, expires_at: tomorrow)

      em = Directory::EffectiveMembership.unscoped.find_by(person_id: person.id, collection_id: entitlement.id)
      expect(em.expires_at).to be_within(1.second).of(tomorrow)
    end
  end

  describe "nesting edge expiry (path_expires_at)" do
    it "excludes effective memberships when the nesting edge expires" do
      group = make_group("grp-a")
      entitlement = make_entitlement("ent-e")
      _, person = make_person

      add_person(group, person)
      nest_group_expired(entitlement, group)

      expect(Directory::EffectiveMembership.where(person_id: person.id, collection_id: entitlement.id)).not_to exist
    end

    it "propagates nesting expiry to effective_memberships.expires_at" do
      group = make_group("grp-b")
      entitlement = make_entitlement("ent-f")
      _, person = make_person
      next_week = 1.week.from_now.change(usec: 0)

      add_person(group, person)
      nest_group(entitlement, group, expires_at: next_week)

      em = Directory::EffectiveMembership.unscoped.find_by(person_id: person.id, collection_id: entitlement.id)
      expect(em.expires_at).to be_within(1.second).of(next_week)
    end

    it "takes the earliest expiry across person membership and nesting edge" do
      group = make_group("grp-c")
      entitlement = make_entitlement("ent-g")
      _, person = make_person
      tomorrow = 1.day.from_now.change(usec: 0)
      next_week = 1.week.from_now.change(usec: 0)

      add_person(group, person, expires_at: tomorrow)
      nest_group(entitlement, group, expires_at: next_week)

      em = Directory::EffectiveMembership.unscoped.find_by(person_id: person.id, collection_id: entitlement.id)
      expect(em.expires_at).to be_within(1.second).of(tomorrow)
    end
  end

  describe "multiple paths with different expiry" do
    it "keeps the most generous expiry when one path never expires" do
      group = make_group("grp-d")
      entitlement = make_entitlement("ent-h")
      _, person = make_person

      add_person(entitlement, person, expires_at: 1.day.from_now)
      add_person(group, person)
      nest_group(entitlement, group)

      em = Directory::EffectiveMembership.unscoped.find_by(person_id: person.id, collection_id: entitlement.id)
      expect(em.expires_at).to be_nil
    end

    it "keeps the longest expiry when both paths expire" do
      group = make_group("grp-e")
      entitlement = make_entitlement("ent-i")
      _, person = make_person
      tomorrow = 1.day.from_now.change(usec: 0)
      next_week = 1.week.from_now.change(usec: 0)

      add_person(entitlement, person, expires_at: tomorrow)
      add_person(group, person, expires_at: next_week)
      nest_group(entitlement, group)

      em = Directory::EffectiveMembership.unscoped.find_by(person_id: person.id, collection_id: entitlement.id)
      expect(em.expires_at).to be_within(1.second).of(next_week)
    end

    it "remains effective when one path expires but another is still active" do
      group = make_group("grp-f")
      entitlement = make_entitlement("ent-j")
      _, person = make_person

      add_person_expired(entitlement, person)
      add_person(group, person)
      nest_group(entitlement, group)

      expect(Directory::EffectiveMembership.where(person_id: person.id, collection_id: entitlement.id)).to exist
    end
  end

  describe "default_scope on EffectiveMembership" do
    it "filters expired rows from standard queries" do
      entitlement = make_entitlement("ent-k")
      _, person = make_person

      add_person(entitlement, person, expires_at: 1.day.from_now)

      em = Directory::EffectiveMembership.unscoped.find_by(person_id: person.id, collection_id: entitlement.id)
      expect(em).to be_present

      ActiveRecord::Base.connection.execute(
        "UPDATE directory_effective_memberships SET expires_at = NOW() - INTERVAL '1 hour' WHERE collection_id = #{entitlement.id} AND person_id = #{person.id}"
      )

      expect(Directory::EffectiveMembership.where(person_id: person.id, collection_id: entitlement.id)).not_to exist
      expect(Directory::EffectiveMembership.unscoped.where(person_id: person.id, collection_id: entitlement.id)).to exist
    end
  end
end
