class IdentityPolicy < ApplicationPolicy
  def index? = user.present?

  def show? = user.present?

  def update? = user.present? && (user.can_break_glass? || user.super_admin?)

  alias_method :clear_slack_id?, :update?

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.super_admin? || user.manual_document_verifier?
        scope.all
      elsif user.organized_programs.any?
        program_ids = user.organized_programs.pluck(:id)
        scope.joins(:access_tokens)
             .where(oauth_access_tokens: { application_id: program_ids })
             .distinct
      else
        scope.none
      end
    end
  end
end
