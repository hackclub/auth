# frozen_string_literal: true

module Directory
  class PersonPolicy < ApplicationPolicy
    def show?
      return true if user.admin?
      return false unless user.person

      viewable_collection_ids = Directory::EffectiveGrant.where(
        person_id: user.person.id,
        permission: %w[view manage_members expose]
      ).select(:target_collection_id)

      Directory::EffectiveMembership.where(
        person_id: record.id,
        collection_id: viewable_collection_ids
      ).exists?
    end

    def create?
      user.admin?
    end

    def destroy?
      user.admin?
    end
  end
end
