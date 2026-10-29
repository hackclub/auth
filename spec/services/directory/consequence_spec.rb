require 'rails_helper'

RSpec.describe Directory::Consequence, type: :model do
  def rebuild!
    Directory::Rebuild.call(cause: 'test')
  end

  describe '.batch_removal_summaries vs .removal_summary' do
    it 'single direct member loses the collection' do
      person = create(:directory_person)
      group = create(:directory_group, name: 'Alpha')
      m = create(:directory_membership, :person, collection: group, member_person: person)
      rebuild!

      single = Directory::Consequence.removal_summary(person: person, collection: group)
      batch = Directory::Consequence.batch_removal_summaries(memberships: [m], collection: group)

      expect(batch[m.id]).to eq(single)
      expect(batch[m.id]).to include('Alpha')
    end

    it 'person in A, A member of B — removing from A loses both' do
      person = create(:directory_person)
      group_a = create(:directory_group, slug: 'a', name: 'A')
      group_b = create(:directory_group, slug: 'b', name: 'B')
      create(:directory_membership, :group, collection: group_b, member_group: group_a)
      m = create(:directory_membership, :person, collection: group_a, member_person: person)
      rebuild!

      single = Directory::Consequence.removal_summary(person: person, collection: group_a)
      batch = Directory::Consequence.batch_removal_summaries(memberships: [m], collection: group_a)

      expect(batch[m.id]).to eq(single)
      expect(batch[m.id]).to include('A')
      expect(batch[m.id]).to include('B')
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

      single = Directory::Consequence.removal_summary(person: person, collection: group_a)
      batch = Directory::Consequence.batch_removal_summaries(memberships: [m_a], collection: group_a)

      expect(batch[m_a.id]).to eq(single)
      # Should only lose A, not C (still reachable via B)
      expect(batch[m_a.id]).to include('A')
      expect(batch[m_a.id]).not_to include('C')
    end

    it 'no consequence when person has another path' do
      person = create(:directory_person)
      group = create(:directory_group, slug: 'g', name: 'G')
      subgroup = create(:directory_group, slug: 'sg', name: 'SubG')
      create(:directory_membership, :group, collection: group, member_group: subgroup)
      m_direct = create(:directory_membership, :person, collection: group, member_person: person)
      create(:directory_membership, :person, collection: subgroup, member_person: person)
      rebuild!

      single = Directory::Consequence.removal_summary(person: person, collection: group)
      batch = Directory::Consequence.batch_removal_summaries(memberships: [m_direct], collection: group)

      # Person still reaches group via subgroup → group closure
      expect(single).to be_nil
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

      s1 = Directory::Consequence.removal_summary(person: p1, collection: group)
      s2 = Directory::Consequence.removal_summary(person: p2, collection: group)
      batch = Directory::Consequence.batch_removal_summaries(memberships: [m1, m2], collection: group)

      expect(batch[m1.id]).to eq(s1)
      expect(batch[m2.id]).to eq(s2)
    end

    it 'deep nesting: A → B → C → D, removing from A loses all' do
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

      single = Directory::Consequence.removal_summary(person: person, collection: a)
      batch = Directory::Consequence.batch_removal_summaries(memberships: [m], collection: a)

      expect(batch[m.id]).to eq(single)
    end

    it 'entitlement: group in entitlement, removing person from group loses both' do
      person = create(:directory_person)
      group = create(:directory_group, slug: 'g', name: 'Engineers')
      ent = create(:directory_entitlement, slug: 'e', name: 'ProdAccess')
      create(:directory_membership, :group, collection: ent, member_group: group)
      m = create(:directory_membership, :person, collection: group, member_person: person)
      rebuild!

      single = Directory::Consequence.removal_summary(person: person, collection: group)
      batch = Directory::Consequence.batch_removal_summaries(memberships: [m], collection: group)

      expect(batch[m.id]).to eq(single)
      expect(batch[m.id]).to include('Engineers')
      expect(batch[m.id]).to include('ProdAccess')
    end
  end
end
