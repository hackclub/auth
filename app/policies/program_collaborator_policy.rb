# frozen_string_literal: true

class ProgramCollaboratorPolicy < ApplicationPolicy
  def accept?
    record.pending? && belongs_to_user?
  end

  def decline?
    record.pending? && belongs_to_user?
  end

  def cancel?
    manage_collaborators?
  end

  private

  def belongs_to_user?
    record.identity_id == user.id ||
      (record.identity_id.nil? && record.invited_email == user.primary_email)
  end

  def manage_collaborators?
    program = record.program
    program.owner_identity_id == user.id || admin?
  end

  def admin?
    backend_user = user.backend_user
    backend_user&.program_manager? || backend_user&.super_admin?
  end
end
