# frozen_string_literal: true

module Directory
  class ExposurePolicy < ApplicationPolicy
    def create?
      user.admin?
    end

    def destroy?
      user.admin?
    end
  end
end
