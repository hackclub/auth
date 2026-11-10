# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Directory::Consequence, type: :model do
  def rebuild!
    Directory::Rebuild.call(cause: 'test')
  end

  describe '.batch_removal_summaries' do
    let(:admin) { Directory::Context.new(identity: nil, person: nil, admin: true) }

    it 'single direct member in a flat group has no consequence' do
      person = create(:directory_person)
      group = create(:directory_group, name: 'Alpha')
      m = create(:directory_membership, :person, collection: group, member_person: person)
      rebuild!

      batch = Directory::Consequence.batch_removal_summaries(memberships: [ m ], collection: group, viewer: admin)

      expect(batch[m.id]).to be_nil
    end

    it 'person in A, A member of B — removing from A loses B' do
      person = create(:directory_person)
      group_a = create(:directory_group, slug: 'a', name: 'A')
      group_b = create(:directory_group, slug: 'b', name: 'B')
      create(:directory_membership, :group, collection: group_b, member_group: group_a)
      m = create(:directory_membership, :person, collection: group_a, member_person: person)
      rebuild!

      batch = Directory::Consequence.batch_removal_summaries(memberships: [ m ], collection: group_a, viewer: admin)

      expect(batch[m.id]).to include('B')
      expect(batch[m.id]).not_to include('A')
    end

    it 'diamond: person in A and B, both in C — removing from A keeps C' do
      person = create(:directory_person)
      group_a = create(:directory_group, slug: 'a', name: 'A')
      group_b = create(:directory_group, slug: 'b', name: 'B')
      group_c = create(:directory_group, slug: 'c', name: 'C')
      create(:directory_membership, :group, collection: group_c, member_group: group_a)
      create(:directory_membership, :group, collection: group_c, member_group: group_b)
      m_a = create(:directory_membership, :person, collection: group_a, member_person: person)
      create(:directory_membership, :person, collection: group_b, member_person: person)
      rebuild!

      batch = Directory::Consequence.batch_removal_summaries(memberships: [ m_a ], collection: group_a, viewer: admin)

      expect(batch[m_a.id]).to be_nil
    end

    it 'no consequence when person has another path' do
      person = create(:directory_person)
      group = create(:directory_group, slug: 'g', name: 'G')
      subgroup = create(:directory_group, slug: 'sg', name: 'SubG')
      create(:directory_membership, :group, collection: group, member_group: subgroup)
      m_direct = create(:directory_membership, :person, collection: group, member_person: person)
      create(:directory_membership, :person, collection: subgroup, member_person: person)
      rebuild!

      batch = Directory::Consequence.batch_removal_summaries(memberships: [ m_direct ], collection: group, viewer: admin)

      # Person still reaches group via subgroup → group closure
      expect(batch[m_direct.id]).to be_nil
    end

    it 'batch handles multiple people correctly' do
      p1 = create(:directory_person)
      p2 = create(:directory_person)
      group = create(:directory_group, slug: 'team', name: 'Team')
      parent = create(:directory_group, slug: 'org', name: 'Org')
      create(:directory_membership, :group, collection: parent, member_group: group)

      m1 = create(:directory_membership, :person, collection: group, member_person: p1)
      m2 = create(:directory_membership, :person, collection: group, member_person: p2)
      rebuild!

      batch = Directory::Consequence.batch_removal_summaries(memberships: [ m1, m2 ], collection: group, viewer: admin)

      expect(batch[m1.id]).to include('Org')
      expect(batch[m1.id]).not_to include('Team')
      expect(batch[m2.id]).to include('Org')
      expect(batch[m2.id]).not_to include('Team')
    end

    it 'deep nesting: A → B → C → D, removing from A loses B, C, D' do
      person = create(:directory_person)
      a = create(:directory_group, slug: 'a', name: 'A')
      b = create(:directory_group, slug: 'b', name: 'B')
      c = create(:directory_group, slug: 'c', name: 'C')
      d = create(:directory_group, slug: 'd', name: 'D')
      create(:directory_membership, :group, collection: b, member_group: a)
      create(:directory_membership, :group, collection: c, member_group: b)
      create(:directory_membership, :group, collection: d, member_group: c)
      m = create(:directory_membership, :person, collection: a, member_person: person)
      rebuild!

      batch = Directory::Consequence.batch_removal_summaries(memberships: [ m ], collection: a, viewer: admin)

      expect(batch[m.id]).to include('B')
      expect(batch[m.id]).to include('C')
      expect(batch[m.id]).to include('D')
      expect(batch[m.id]).not_to include('A')
    end

    it 'entitlement: group in entitlement, removing person from group loses the entitlement' do
      person = create(:directory_person)
      group = create(:directory_group, slug: 'g', name: 'Engineers')
      ent = create(:directory_entitlement, slug: 'e', name: 'ProdAccess')
      create(:directory_membership, :group, collection: ent, member_group: group)
      m = create(:directory_membership, :person, collection: group, member_person: person)
      rebuild!

      batch = Directory::Consequence.batch_removal_summaries(memberships: [ m ], collection: group, viewer: admin)

      expect(batch[m.id]).to include('ProdAccess')
      expect(batch[m.id]).not_to include('Engineers')
    end

    it "only names collections the viewer can see" do
      viewer_person = create(:directory_person)
      person = create(:directory_person)
      team = create(:directory_group, slug: "team", name: "Team")
      secret = create(:directory_entitlement, slug: "secret", name: "Top Secret Ent")
      open_ent = create(:directory_entitlement, slug: "open", name: "Open Ent")
      grantee = create(:directory_group, slug: "grantee")
      create(:directory_membership, :group, collection: secret, member_group: team)
      create(:directory_membership, :group, collection: open_ent, member_group: team)
      create(:directory_membership, :person, collection: grantee, member_person: viewer_person)
      Directory::Grant.create!(grantee_group: grantee, target_collection: open_ent, permission: "view")
      m = create(:directory_membership, :person, collection: team, member_person: person)
      rebuild!

      viewer = Directory::Context.new(identity: viewer_person.identity, person: viewer_person, admin: false)
      batch = Directory::Consequence.batch_removal_summaries(memberships: [ m ], collection: team, viewer: viewer)

      expect(batch[m.id]).to eq("will lose Open Ent (+1 you can't see)")
      expect(batch[m.id]).not_to include("Top Secret")
    end

    describe "apps" do
      let(:app) { create(:program, :with_groups, name: "Gated App") }

      it "names the apps a person loses when removed from the entitlement itself" do
        person = create(:directory_person)
        ent = create(:directory_entitlement, name: "Staff")
        Directory::Exposure.create!(app: app, entitlement: ent, claim_name: "staff")
        m = create(:directory_membership, :person, collection: ent, member_person: person)
        rebuild!

        batch = Directory::Consequence.batch_removal_summaries(memberships: [ m ], collection: ent, viewer: admin)

        expect(batch[m.id]).to eq("will lose access to Gated App")
      end

      it "doesn't count a requirement app the person still qualifies for another way" do
        person = create(:directory_person)
        e1 = create(:directory_entitlement, name: "E1")
        e2 = create(:directory_entitlement, name: "E2")
        Directory::AppRequirement.create!(app: app, entitlement: e1)
        Directory::AppRequirement.create!(app: app, entitlement: e2)
        m = create(:directory_membership, :person, collection: e1, member_person: person)
        create(:directory_membership, :person, collection: e2, member_person: person)
        rebuild!

        batch = Directory::Consequence.batch_removal_summaries(memberships: [ m ], collection: e1, viewer: admin)
        expect(batch[m.id]).to be_nil

        other = create(:directory_person)
        m2 = create(:directory_membership, :person, collection: e1, member_person: other)
        rebuild!

        batch = Directory::Consequence.batch_removal_summaries(memberships: [ m2 ], collection: e1, viewer: admin)
        expect(batch[m2.id]).to eq("will lose access to Gated App")
      end

      it "summarises a nested group's removal across its people" do
        p1 = create(:directory_person)
        p2 = create(:directory_person)
        team = create(:directory_group, name: "Team")
        ent = create(:directory_entitlement, name: "Staff")
        Directory::Exposure.create!(app: app, entitlement: ent, claim_name: "staff")
        m = create(:directory_membership, :group, collection: ent, member_group: team)
        create(:directory_membership, :person, collection: team, member_person: p1)
        create(:directory_membership, :person, collection: team, member_person: p2)
        create(:directory_membership, :person, collection: ent, member_person: p2)
        rebuild!

        batch = Directory::Consequence.batch_removal_summaries(memberships: [ m ], collection: ent, viewer: admin)

        expect(batch[m.id]).to eq("1 person will lose Staff and access to Gated App")
      end

      it "counts apps lost only through hidden entitlements instead of naming them" do
        viewer_person = create(:directory_person)
        person = create(:directory_person)
        team = create(:directory_group, slug: "team2", name: "Team")
        secret = create(:directory_entitlement, name: "Secret")
        Directory::Exposure.create!(app: app, entitlement: secret, claim_name: "secret")
        create(:directory_membership, :group, collection: secret, member_group: team)
        m = create(:directory_membership, :person, collection: team, member_person: person)
        rebuild!

        viewer = Directory::Context.new(identity: viewer_person.identity, person: viewer_person, admin: false)
        batch = Directory::Consequence.batch_removal_summaries(memberships: [ m ], collection: team, viewer: viewer)

        expect(batch[m.id]).to eq("will lose access through 2 things you can't see")
        expect(batch[m.id]).not_to include("Gated App")
      end
    end
  end
end
