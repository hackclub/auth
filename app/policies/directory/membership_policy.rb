# frozen_string_literal: true

module Directory
  class MembershipPolicy < ApplicationPolicy
    def create?
      collection = record.is_a?(Directory::Membership) ? record.collection : record
      return true if user.admin?

      user.can?(:manage_members, collection)
    end

    def destroy?
      create?
    end
  end
end
