# frozen_string_literal: true

module Directory
  class GrantPolicy < ApplicationPolicy
    def index?
      user.admin?
    end

    def create?
      user.admin?
    end

    def destroy?
      user.admin?
    end
  end
end
