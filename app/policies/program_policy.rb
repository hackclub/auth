# frozen_string_literal: true

# `user` here is always an Identity (via IdentityAuthorizable).
class ProgramPolicy < ApplicationPolicy
  def index?
    user.developer_mode? || admin?
  end

  def show?
    owner? || collaborator? || admin?
  end

  def create?
    user.developer_mode? || admin?
  end

  def new?
    create?
  end

  def update?
    owner? || collaborator? || admin?
  end

  def edit?
    update?
  end

  def destroy?
    owner? || admin?
  end

  def update_trust_level?
    user.can_hq_officialize? || admin?
  end

  def update_scopes?
    owner? || collaborator? || admin?
  end

  def update_all_scopes?
    admin?
  end

  # Returns the list of scope names this user is permitted to add or remove.
  # Scopes outside this list that already exist on the app are "locked" —
  # preserved on save but not editable by this user.
  def allowed_scopes
    if super_admin?
      OAuthScope::SUPER_ADMIN_SCOPES
    elsif user.can_hq_officialize? || admin?
      OAuthScope::HQ_OFFICIAL_SCOPES
    else
      OAuthScope::COMMUNITY_ALLOWED
    end
  end

  def update_onboarding_scenario?
    super_admin?
  end

  def update_active?
    admin?
  end

  def view_secret?
    owner? || admin?
  end

  def view_api_key?
    admin?
  end

  def rotate_credentials?
    owner? || admin?
  end

  def revoke_all_authorizations?
    owner? || admin?
  end

  def manage_collaborators?
    owner?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if admin?
        scope.all
      else
        user.accessible_developer_apps
      end
    end

    private

    def admin?
      backend_user = user.backend_user
      backend_user&.program_manager? || backend_user&.super_admin?
    end
  end

  private

  def owner?
    record.is_a?(Class) ? false : record.owner_identity_id == user.id
  end

  def collaborator?
    record.is_a?(Class) ? false : record.collaborator?(user)
  end

  def admin?
    backend_user = user.backend_user
    backend_user&.program_manager? || backend_user&.super_admin?
  end

  def super_admin?
    user.backend_user&.super_admin?
  end
end
