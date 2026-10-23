# frozen_string_literal: true

module Directory
  class CollectionPolicy < ApplicationPolicy
    def index?
      user.admin? || user.person.present?
    end

    def show?
      user.admin? || user.can_any?(%w[view manage_members expose], record)
    end

    def create?
      user.admin?
    end

    def update?
      user.admin?
    end

    def destroy?
      user.admin?
    end

    class Scope < ApplicationPolicy::Scope
      def resolve
        if user.admin?
          scope.all
        elsif user.person
          collection_ids = Directory::EffectiveGrant.where(person_id: user.person.id).select(:target_collection_id)
          scope.where(id: collection_ids)
        else
          scope.none
        end
      end
    end
  end
end
