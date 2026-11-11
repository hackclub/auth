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

  # an entitlement the actor can't see answers like one that doesn't exist
  def find_visible_entitlement!(slug)
    entitlement = Directory::Collection.entitlements.find_by!(slug: slug)
    raise ActiveRecord::RecordNotFound unless Directory::CollectionPolicy.new(directory_context, entitlement).show?

    entitlement
  end

  # the page the wiring form was on: the developer app page or the directory's app page,
  # never anywhere else
  def wiring_return_path(app)
    allowed = [ developer_app_path(app), directory_app_path(app) ]
    allowed.include?(params[:return_to]) ? params[:return_to] : developer_app_path(app)
  end

  # whether to show the wire/require forms at all
  def can_wire_any_entitlement?(app)
    directory_context.admin? || (app_owner?(app) && directory_context.can_expose_any_entitlement?)
  end

  # app pages are seen by collaborators with no directory rights, so directory content on
  # them (descriptions, whether an exposure exists) follows directory visibility
  def entitlement_visible?(entitlement)
    Directory::CollectionPolicy.new(directory_context, entitlement).show?
  end

  # the entitlements this person may wire to app, for the wiring forms' pickers
  def wireable_entitlements(app)
    scope = Directory::Collection.where(kind: "entitlement").order(:name)
    return scope if directory_context.admin?
    return scope.none unless app_owner?(app) && directory_context.person

    scope.where(id: Directory::EffectiveGrant.where(person_id: directory_context.person.id, permission: "expose").select(:target_collection_id))
  end

  def authorize_app_entitlement_wiring!(app, entitlement)
    raise Pundit::NotAuthorizedError unless app.hq_official? && can_manage_app_wiring?(app, entitlement)
  end

  def authorize_app_entitlement_unwiring!(app, entitlement)
    raise Pundit::NotAuthorizedError unless can_manage_app_wiring?(app, entitlement)
  end
end
