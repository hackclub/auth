class VerificationFormPolicy < ApplicationPolicy
  def new?
    # Anyone logged in can submit a verification
    user.present?
  end

  def create? = new?

  def show? = new?

  def update? = new?
end
