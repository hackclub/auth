class VerificationFormPolicy < ApplicationPolicy
  def new?
    # Anyone logged in can submit a verification
    user.present?
  end

  def create?
    new?
  end

  def show?
    new?
  end

  def update?
    new?
  end
end
