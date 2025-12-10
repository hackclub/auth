class ProgramPolicy < ApplicationPolicy
  def index? = user_is_program_manager? || user_has_assigned_programs?

  def show? = user_is_program_manager? || user_has_access_to_program?

  def create? = user_is_program_manager?

  def update? = user_is_program_manager? || user_has_access_to_program?

  def destroy? = user_is_program_manager?

  def update_basic_fields? = user_has_access_to_program?

  def update_scopes? = user_is_program_manager?

  def update_onboarding_scenario? = user&.super_admin?

  class Scope < Scope
    def resolve
      if user.program_manager? || user.super_admin?
        # Program managers and super admins can see all programs
        scope.all
      else
        # Regular users can only see programs they are assigned to
        scope.joins(:organizer_positions).where(backend_organizer_positions: { backend_user_id: user.id })
      end
    end
  end

  private

  def user_is_program_manager?
    user.present? && (user.program_manager? || user.super_admin?)
  end

  def user_has_assigned_programs?
    user.present? && user.organized_programs.any?
  end

  def user_has_access_to_program?
    user_is_program_manager? || (user.present? && user.organized_programs.include?(record))
  end
end
