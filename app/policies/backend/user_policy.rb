class Backend::UserPolicy < ApplicationPolicy
  def index? = user&.present?

  def show? = user&.present?

  def create? = user&.super_admin?

  def update? = user&.super_admin?

  def deactivate? = user&.super_admin?

  alias_method :activate?, :deactivate?
end
