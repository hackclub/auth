# frozen_string_literal: true

module Directory
  class BaseController < ::ApplicationController
    include Pundit::Authorization
    layout "directory"

    rescue_from Pundit::NotAuthorizedError do
      redirect_back fallback_location: directory_root_path, alert: t("directory.flash.not_authorized")
    end

    before_action :authenticate_identity!
    before_action :ensure_directory_access!
    after_action :verify_authorized, unless: :skip_authorization?

    helper_method :current_directory_person, :directory_admin?, :breadcrumbs

    private

    def current_directory_person
      @current_directory_person ||= Directory::Person.find_by(identity: current_identity)
    end

    def directory_admin?
      current_identity&.backend_user&.directory_services_admin?
    end

    def ensure_directory_access!
      return if directory_admin?
      return if current_directory_person && Directory::EffectiveGrant.where(person_id: current_directory_person.id).exists?
      return if current_directory_person && controller_name == "my_access"

      raise ActionController::RoutingError, "Not Found"
    end

    def pundit_user
      Directory::Context.new(identity: current_identity, person: current_directory_person, admin: directory_admin?)
    end

    def skip_authorization?
      false
    end

    def add_breadcrumb(label, path = nil)
      @_breadcrumbs ||= [ { label: "directory", path: directory_root_path } ]
      @_breadcrumbs << { label:, path: }
    end

    def breadcrumbs
      @_breadcrumbs || [ { label: "directory", path: directory_root_path } ]
    end

    def user_for_public_activity
      current_identity
    end
  end
end
