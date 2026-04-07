class AddressPolicy < ApplicationPolicy
  # user is either an Identity (public) or Backend::User (admin)
  def show?    = owns? || super_admin?
  def create?  = owns? || super_admin?
  def update?  = owns? || super_admin?
  def destroy? = owns? || super_admin?

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.is_a?(Identity)
        scope.where(identity: user)
      elsif user.is_a?(Backend::User) && user.super_admin?
        scope.all
      else
        scope.none
      end
    end
  end

  private

  def owns?
    user.is_a?(Identity) && record.identity == user
  end

  def super_admin?
    if user.is_a?(Backend::User)
      user.super_admin?
    elsif user.is_a?(Identity)
      user.backend_user&.super_admin?
    else
      false
    end
  end
end
