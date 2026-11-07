# frozen_string_literal: true

module DirectoryAppAuthorization
  extend ActiveSupport::Concern

  private

  def app_owner?(app)
    app.owner_identity_id == current_identity.id ||
      ProgramCollaborator.where(program_id: app.id, identity_id: current_identity.id, status: "accepted").exists?
  end

  def directory_context
    @directory_context ||= begin
      person = Directory::Person.find_by(identity: current_identity)
      admin = current_identity.backend_user&.directory_services_admin?
      Directory::Context.new(identity: current_identity, person: person, admin: admin)
    end
  end

  def authorize_app_entitlement_wiring!(app, entitlement)
    unless app_owner?(app) && directory_context.can?(:expose, entitlement) && app.hq_official?
      raise Pundit::NotAuthorizedError
    end
  end

  def authorize_app_entitlement_unwiring!(app, entitlement)
    return if directory_context.admin?
    unless app_owner?(app) && directory_context.can?(:expose, entitlement)
      raise Pundit::NotAuthorizedError
    end
  end
end
