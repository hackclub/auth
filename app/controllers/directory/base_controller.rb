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

    helper_method :current_directory_person, :directory_admin?, :breadcrumbs, :directory_keyboard_shortcuts

    private

    # For pages that only read: a record the viewer can't see answers the same 404 as one
    # that doesn't exist, so slugs and public ids can't be probed.
    def authorize_visible!(record, query = :show?)
      authorize record, query
    rescue Pundit::NotAuthorizedError
      raise ActiveRecord::RecordNotFound
    end

    # Owners, trackables and whatever the directory partials reach through them, in a
    # handful of queries instead of a few per row.
    def preload_activities(activities)
      records = activities.to_a
      ActiveRecord::Associations::Preloader.new(records: records, associations: :owner).call
      ActiveRecord::Associations::Preloader.new(records: records, associations: :trackable).call

      trackables = records.filter_map(&:trackable).group_by(&:class)
      {
        Directory::Grant => %i[grantee_group target_collection],
        Directory::Person => :identity
      }.each do |klass, associations|
        next unless trackables[klass]
        ActiveRecord::Associations::Preloader.new(records: trackables[klass], associations: associations).call
      end
      activities
    end

    def current_directory_person
      return @current_directory_person if instance_variable_defined?(:@current_directory_person)
      @current_directory_person = Directory::Person.find_by(identity: current_identity)
    end

    def directory_admin?
      current_identity&.backend_user&.directory_services_admin?
    end

    def ensure_directory_access!
      return if directory_admin?
      return if current_directory_person && pundit_user.has_any_grants?

      raise ActionController::RoutingError, "Not Found"
    end

    def pundit_user
      @_pundit_user ||= Directory::Context.new(identity: current_identity, person: current_directory_person, admin: directory_admin?).tap do |ctx|
        ctx.preload_grants! unless directory_admin?
      end
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

    def directory_keyboard_shortcuts
      shortcuts = {}
      parent = breadcrumbs[-2]
      shortcuts[:back] = parent[:path] if parent&.dig(:path)
      shortcuts
    end

    def directory_kbar_data
      shortcuts = [
        { code: "DRCT", label: "Directory home", path: directory_root_path, icon: "⌂" },
        { code: "MYAX", label: "My access", path: directory_my_access_path, icon: "⭢" },
        { code: "DSRC", label: "Search", path: directory_search_path, icon: "⌕" }
      ]
      if directory_admin?
        shortcuts += [
          { code: "DPPL", label: "People", path: directory_people_path, icon: "⭢" },
          { code: "DGRT", label: "Grants", path: directory_all_grants_path, icon: "⭢" },
          { code: "DRPT", label: "Reports", path: directory_reports_path, icon: "⭢" },
          { code: "DHLT", label: "Health", path: directory_health_path, icon: "⭢" },
          { code: "DIMP", label: "Import", path: directory_new_import_path, icon: "⭢" },
          { code: "DACT", label: "Activity", path: directory_activity_path, icon: "⭢" },
          { code: "DVAS", label: "View as", path: directory_view_as_path, icon: "⭢" }
        ]
      end
      if current_identity.active_for_backend?
        shortcuts << { code: "BKND", label: "Backend", path: backend_root_path, icon: "⭠" }
      end

      search_scopes = [ { key: "directory", label: "Directory", icon: "⭢" } ]

      { shortcuts: shortcuts, searchScopes: search_scopes, searchUrl: directory_search_kbar_path, defaultScope: "directory" }
    end
    helper_method :directory_kbar_data
  end
end
