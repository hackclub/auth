class AddressPolicy < ApplicationPolicy
  include IdentityAware

  def index?
    true
  end

  def show?
    owns? || super_admin?
  end

  def create?
    owns? || super_admin?
  end

  def update?
    owns? || super_admin?
  end

  def destroy?
    owns? || super_admin?
  end

  class Scope < ApplicationPolicy::Scope
    include IdentityAware

    def resolve
      if super_admin?
        scope.all
      else
        scope.where(identity: user)
      end
    end
  end

  private
end
