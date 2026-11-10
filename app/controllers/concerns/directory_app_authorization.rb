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
      admin = directory_admin_session?
      Directory::Context.new(identity: current_identity, person: person, admin: admin)
    end
  end

  # Directory admins can wire and unwire any app; owners can on their own app, for
  # entitlements they hold expose on. Only hq_official apps get new wiring, but anyone
  # allowed to wire can always unwire (e.g. after an app is downgraded).
  def can_manage_app_wiring?(app, entitlement)
    directory_context.admin? || (app_owner?(app) && directory_context.can?(:expose, entitlement))
  end

  # whether to show the wire/require forms at all
  def can_wire_any_entitlement?(app)
    directory_context.admin? || (app_owner?(app) && directory_context.can_on_any?(:expose))
  end

  def authorize_app_entitlement_wiring!(app, entitlement)
    raise Pundit::NotAuthorizedError unless app.hq_official? && can_manage_app_wiring?(app, entitlement)
  end

  def authorize_app_entitlement_unwiring!(app, entitlement)
    raise Pundit::NotAuthorizedError unless can_manage_app_wiring?(app, entitlement)
  end
end
