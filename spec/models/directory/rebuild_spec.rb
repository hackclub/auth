require 'rails_helper'

RSpec.describe Directory::Rebuild, type: :model do
  def rebuild!(cause: 'test')
    Directory::Rebuild.call(cause: cause)
  end

  def effective_collection_ids_for(person)
    Directory::EffectiveMembership.where(person_id: person.id).pluck(:collection_id)
  end

  def effective_grants_for(person)
    Directory::EffectiveGrant.where(person_id: person.id).pluck(:target_collection_id, :permission)
  end

  describe 'basic: person in a group' do
    it 'creates effective membership' do
      person = create(:directory_person)
      group = create(:directory_group)
      create(:directory_membership, :person, collection: group, member_person: person)

      rebuild!

      expect(effective_collection_ids_for(person)).to contain_exactly(group.id)
    end
  end

  describe 'nesting: person in A, A member of B' do
    it 'person is effective member of both A and B' do
      person = create(:directory_person)
      group_a = create(:directory_group, slug: 'a', name: 'A')
      group_b = create(:directory_group, slug: 'b', name: 'B')

      create(:directory_membership, :person, collection: group_a, member_person: person)
      create(:directory_membership, :group, collection: group_b, member_group: group_a)

      rebuild!

      expect(effective_collection_ids_for(person)).to contain_exactly(group_a.id, group_b.id)
    end
  end

  describe 'diamond path: person in A and B, both members of C' do
    it 'person is effective member of A, B, and C with no duplicates' do
      person = create(:directory_person)
      group_a = create(:directory_group, slug: 'a', name: 'A')
      group_b = create(:directory_group, slug: 'b', name: 'B')
      group_c = create(:directory_group, slug: 'c', name: 'C')

      create(:directory_membership, :person, collection: group_a, member_person: person)
      create(:directory_membership, :person, collection: group_b, member_person: person)
      create(:directory_membership, :group, collection: group_c, member_group: group_a)
      create(:directory_membership, :group, collection: group_c, member_group: group_b)

      rebuild!

      expect(effective_collection_ids_for(person)).to contain_exactly(group_a.id, group_b.id, group_c.id)

      # No duplicate rows
      count = Directory::EffectiveMembership.where(person_id: person.id, collection_id: group_c.id).count
      expect(count).to eq(1)
    end

    it 'closure includes all ancestor paths' do
      group_a = create(:directory_group, slug: 'a', name: 'A')
      group_b = create(:directory_group, slug: 'b', name: 'B')
      group_c = create(:directory_group, slug: 'c', name: 'C')

      create(:directory_membership, :group, collection: group_c, member_group: group_a)
      create(:directory_membership, :group, collection: group_c, member_group: group_b)

      rebuild!

      # C is ancestor (parent), A and B are descendants (children/members)
      expect(Directory::Closure.where(ancestor_id: group_c.id, descendant_id: group_a.id)).to exist
      expect(Directory::Closure.where(ancestor_id: group_c.id, descendant_id: group_b.id)).to exist
    end
  end

  describe 'multiple parents: A member of both B and C' do
    it 'person in A is effective member of A, B, and C' do
      person = create(:directory_person)
      group_a = create(:directory_group, slug: 'a', name: 'A')
      group_b = create(:directory_group, slug: 'b', name: 'B')
      group_c = create(:directory_group, slug: 'c', name: 'C')

      create(:directory_membership, :person, collection: group_a, member_person: person)
      create(:directory_membership, :group, collection: group_b, member_group: group_a)
      create(:directory_membership, :group, collection: group_c, member_group: group_a)

      rebuild!

      expect(effective_collection_ids_for(person)).to contain_exactly(group_a.id, group_b.id, group_c.id)
    end
  end

  describe 'entitlement: group A member of entitlement E, person in A' do
    it 'person is effective member of A and E' do
      person = create(:directory_person)
      group_a = create(:directory_group, slug: 'a', name: 'A')
      entitlement = create(:directory_entitlement, slug: 'ent', name: 'Ent')

      create(:directory_membership, :person, collection: group_a, member_person: person)
      create(:directory_membership, :group, collection: entitlement, member_group: group_a)

      rebuild!

      expect(effective_collection_ids_for(person)).to contain_exactly(group_a.id, entitlement.id)
    end
  end

  describe 'direct person in entitlement' do
    it 'person is effective member of E' do
      person = create(:directory_person)
      entitlement = create(:directory_entitlement, slug: 'ent', name: 'Ent')

      create(:directory_membership, :person, collection: entitlement, member_person: person)

      rebuild!

      expect(effective_collection_ids_for(person)).to contain_exactly(entitlement.id)
    end
  end

  describe 'cycle rejection' do
    it 'rejects direct cycle: A member of B, B member of A' do
      group_a = create(:directory_group, slug: 'a', name: 'A')
      group_b = create(:directory_group, slug: 'b', name: 'B')

      create(:directory_membership, :group, collection: group_b, member_group: group_a)

      membership = build(:directory_membership, :group, collection: group_a, member_group: group_b)
      expect(membership).not_to be_valid
      expect(membership.errors[:base]).to include(a_string_matching(/cycle/i))
    end

    it 'rejects indirect cycle: A→B, B→C, C→A' do
      group_a = create(:directory_group, slug: 'a', name: 'A')
      group_b = create(:directory_group, slug: 'b', name: 'B')
      group_c = create(:directory_group, slug: 'c', name: 'C')

      create(:directory_membership, :group, collection: group_b, member_group: group_a)
      create(:directory_membership, :group, collection: group_c, member_group: group_b)

      membership = build(:directory_membership, :group, collection: group_a, member_group: group_c)
      expect(membership).not_to be_valid
      expect(membership.errors[:base]).to include(a_string_matching(/cycle/i))
    end
  end

  describe 'depth limit' do
    it 'rejects nesting beyond depth 6' do
      groups = Array.new(7) { |i| create(:directory_group, slug: "depth-#{i}", name: "Depth #{i}") }

      # Chain: group[0] in group[1], group[1] in group[2], ..., group[5] in group[6] — depth 6, ok
      6.times do |i|
        create(:directory_membership, :group, collection: groups[i + 1], member_group: groups[i])
      end

      # Adding group[6] into group[7] would be depth 7
      group_7 = create(:directory_group, slug: 'depth-7', name: 'Depth 7')
      membership = build(:directory_membership, :group, collection: group_7, member_group: groups[6])
      expect(membership).not_to be_valid
      expect(membership.errors[:base]).to include(a_string_matching(/depth/i))
    end

    it 'allows nesting at exactly depth 6' do
      groups = Array.new(7) { |i| create(:directory_group, slug: "ok-depth-#{i}", name: "OK Depth #{i}") }

      6.times do |i|
        create(:directory_membership, :group, collection: groups[i + 1], member_group: groups[i])
      end

      person = create(:directory_person)
      membership = build(:directory_membership, :person, collection: groups[0], member_person: person)
      expect(membership).to be_valid
    end
  end

  describe 'protected stops recursive grants' do
    it 'grant expansion stops at protected collection' do
      grantee_group = create(:directory_group, slug: 'grantee', name: 'Grantee')
      person = create(:directory_person)
      create(:directory_membership, :person, collection: grantee_group, member_person: person)

      group_a = create(:directory_group, slug: 'a', name: 'A')
      group_b = create(:directory_group, slug: 'b', name: 'B')
      group_c = create(:directory_group, slug: 'c', name: 'C', protected: true)

      create(:directory_membership, :group, collection: group_a, member_group: group_b)
      create(:directory_membership, :group, collection: group_b, member_group: group_c)

      create(:directory_grant, grantee_group: grantee_group, target_collection: group_a, permission: 'view', recursive: true)

      rebuild!

      grants = effective_grants_for(person)
      expect(grants).to include([ group_a.id, 'view' ])
      expect(grants).to include([ group_b.id, 'view' ])
      expect(grants).not_to include([ group_c.id, 'view' ])
    end
  end

  describe 'grant expansion' do
    it 'non-recursive grant does not extend to children' do
      grantee_group = create(:directory_group, slug: 'grantee', name: 'Grantee')
      person = create(:directory_person)
      create(:directory_membership, :person, collection: grantee_group, member_person: person)

      target = create(:directory_group, slug: 'target', name: 'Target')
      child = create(:directory_group, slug: 'child', name: 'Child')
      create(:directory_membership, :group, collection: target, member_group: child)

      create(:directory_grant, grantee_group: grantee_group, target_collection: target, permission: 'manage_members')

      rebuild!

      grants = effective_grants_for(person)
      expect(grants).to include([ target.id, 'manage_members' ])
      expect(grants).not_to include([ child.id, 'manage_members' ])
    end

    it 'recursive grant extends to children' do
      grantee_group = create(:directory_group, slug: 'grantee', name: 'Grantee')
      person = create(:directory_person)
      create(:directory_membership, :person, collection: grantee_group, member_person: person)

      target = create(:directory_group, slug: 'target', name: 'Target')
      child = create(:directory_group, slug: 'child', name: 'Child')
      create(:directory_membership, :group, collection: target, member_group: child)

      create(:directory_grant, grantee_group: grantee_group, target_collection: target, permission: 'manage_members', recursive: true)

      rebuild!

      grants = effective_grants_for(person)
      expect(grants).to include([ target.id, 'manage_members' ])
      expect(grants).to include([ child.id, 'manage_members' ])
    end
  end

  describe 'outbox: membership changes' do
    it 'records added when person joins group' do
      person = create(:directory_person)
      group = create(:directory_group)
      create(:directory_membership, :person, collection: group, member_person: person)

      rebuild!(cause: 'join-test')

      change = Directory::MembershipChange.find_by(collection_id: group.id, person_id: person.id, op: 'added')
      expect(change).to be_present
      expect(change.cause).to eq('join-test')
    end

    it 'records removed when person leaves group' do
      person = create(:directory_person)
      group = create(:directory_group)
      membership = create(:directory_membership, :person, collection: group, member_person: person)

      rebuild!(cause: 'setup')

      membership.destroy!

      rebuild!(cause: 'leave-test')

      change = Directory::MembershipChange.find_by(collection_id: group.id, person_id: person.id, op: 'removed')
      expect(change).to be_present
      expect(change.cause).to eq('leave-test')
    end
  end

  describe 'idempotency' do
    it 'second rebuild with no changes produces no new change rows' do
      person = create(:directory_person)
      group = create(:directory_group)
      create(:directory_membership, :person, collection: group, member_person: person)

      rebuild!(cause: 'first')

      count_before = Directory::MembershipChange.count

      rebuild!(cause: 'second')

      expect(Directory::MembershipChange.count).to eq(count_before)
    end
  end

  describe 'grant validations' do
    it 'rejects recursive grant targeting an entitlement' do
      grantee = create(:directory_group)
      target = create(:directory_entitlement)

      grant = build(:directory_grant, grantee_group: grantee, target_collection: target, permission: 'view', recursive: true)
      expect(grant).not_to be_valid
    end

    it 'rejects entitlement as grantee' do
      entitlement = create(:directory_entitlement)
      target = create(:directory_group)

      grant = build(:directory_grant, grantee_group: entitlement, target_collection: target, permission: 'view')
      expect(grant).not_to be_valid
    end
  end

  describe 'membership kind matrix' do
    it 'rejects entitlement as member_group' do
      entitlement = create(:directory_entitlement)
      group = create(:directory_group)

      membership = build(:directory_membership, :group, collection: group, member_group: entitlement)
      expect(membership).not_to be_valid
    end

    it 'allows group as member of entitlement' do
      group = create(:directory_group)
      entitlement = create(:directory_entitlement)

      membership = build(:directory_membership, :group, collection: entitlement, member_group: group)
      expect(membership).to be_valid
    end

    it 'allows group as member of group' do
      group_a = create(:directory_group, slug: 'a', name: 'A')
      group_b = create(:directory_group, slug: 'b', name: 'B')

      membership = build(:directory_membership, :group, collection: group_b, member_group: group_a)
      expect(membership).to be_valid
    end

    it 'allows person in group' do
      person = create(:directory_person)
      group = create(:directory_group)

      membership = build(:directory_membership, :person, collection: group, member_person: person)
      expect(membership).to be_valid
    end

    it 'allows person in entitlement' do
      person = create(:directory_person)
      entitlement = create(:directory_entitlement)

      membership = build(:directory_membership, :person, collection: entitlement, member_person: person)
      expect(membership).to be_valid
    end
  end
end
