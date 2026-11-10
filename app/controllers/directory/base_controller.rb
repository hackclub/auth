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

    helper_method :current_directory_person, :directory_admin?, :breadcrumbs, :directory_keyboard_shortcuts,
      :directory_activity_owner, :directory_browsable?, :directory_home_path,
      :collection_link, :collection_label, :activity_member_name, :activity_grantee_name

    private

    # For pages that only read: a record the viewer can't see answers the same 404 as one
    # that doesn't exist, so slugs and public ids can't be probed.
    def authorize_visible!(record, query = :show?)
      authorize record, query
    rescue Pundit::NotAuthorizedError
      raise ActiveRecord::RecordNotFound
    end

    # For writes: look up a collection the way a read would see it, so "exists but hidden"
    # and "doesn't exist" give the same answer before authorization says anything.
    def find_visible_collection!(slug)
      collection = Directory::Collection.find_by(slug: slug)
      raise ActiveRecord::RecordNotFound unless collection && (directory_admin? || collection_visible?(collection))

      collection
    end

    # Owners, trackables and whatever the directory partials reach through them, in a
    # handful of queries instead of a few per row.
    def preload_activities(activities)
      records = activities.to_a
      ActiveRecord::Associations::Preloader.new(records: records, associations: :owner).call

      owners = records.map(&:owner).grep(::Identity).uniq
      ActiveRecord::Associations::Preloader.new(records: owners, associations: :directory_person).call
      owner_people = owners.filter_map(&:directory_person)
      visible = policy_scope(Directory::Person).where(id: owner_people.map(&:id)).pluck(:id).to_set
      activity_owner_visibility.merge!(owner_people.to_h { |p| [ p.id, visible.include?(p.id) ] })
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

    # Activity owners link to their directory page when the viewer can open it, else plain
    # text: the backend identity page the shared snippet would link to isn't theirs to open.
    # a Backend::User owner (backend actions like GDPR deletion) is shown as its identity;
    # backend usernames and links aren't for directory viewers
    def directory_activity_owner(owner)
      owner = owner.identity if owner.is_a?(::Backend::User)
      return Components::DirectoryOwnerMention.new(name: t("directory.activity.staff")) unless owner

      person = owner.directory_person
      href = directory_person_path(person) if person && activity_owner_visible?(person)
      Components::DirectoryOwnerMention.new(name: "#{owner.first_name} #{owner.last_name}", href:)
    end

    # Collections the viewer can't open are named "a group you can't see", never linked.
    def collection_link(collection)
      return helpers.tag.span(t("directory.hidden_group"), style: "opacity: 0.5;") unless collection_visible?(collection)

      helpers.link_to(collection.name, directory_collection_path(collection.slug))
    end

    def collection_label(collection) = collection_visible?(collection) ? collection.name : t("directory.hidden_group")

    def activity_member_name(activity)
      params = activity.parameters
      return params["member_name"] unless params["member_type"] == "group"

      group = Directory::Collection.find_by(id: params["member_group_id"]) if params["member_group_id"]
      group && collection_visible?(group) ? params["member_name"] : t("directory.hidden_group")
    end

    # a grant row names its grantee group only to viewers who can see that group; once the
    # grant is gone there's nothing left to check, so only admins get the stored name
    def activity_grantee_name(activity)
      group = activity.trackable.try(:grantee_group)
      return collection_label(group) if group
      return activity.parameters["grantee_name"] || "?" if directory_admin?

      t("directory.hidden_group")
    end

    def collection_visible?(collection)
      @collection_visibility ||= {}
      @collection_visibility.fetch(collection.id) { @collection_visibility[collection.id] = policy(collection).show? }
    end

    def activity_owner_visible?(person)
      activity_owner_visibility.fetch(person.id) { activity_owner_visibility[person.id] = policy(person).show? }
    end

    def activity_owner_visibility
      @activity_owner_visibility ||= {}
    end

    def current_directory_person
      return @current_directory_person if instance_variable_defined?(:@current_directory_person)
      @current_directory_person = Directory::Person.find_by(identity: current_identity)
    end

    def directory_admin? = directory_admin_session?

    def ensure_directory_access!
      raise ActionController::RoutingError, "Not Found" unless directory_browsable?
    end

    # Members with no grants only get /directory/me; everything else 404s for them.
    def directory_browsable?
      return @directory_browsable if defined?(@directory_browsable)
      @directory_browsable = !!(directory_admin? || (current_directory_person && pundit_user.has_any_grants?))
    end

    def directory_home_path
      directory_browsable? ? directory_root_path : directory_my_access_path
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
      @_breadcrumbs ||= [ { label: "directory", path: directory_home_path } ]
      @_breadcrumbs << { label:, path: }
    end

    def breadcrumbs
      @_breadcrumbs || [ { label: "directory", path: directory_home_path } ]
    end

    def directory_keyboard_shortcuts
      shortcuts = {}
      parent = breadcrumbs[-2]
      shortcuts[:back] = parent[:path] if parent&.dig(:path)
      shortcuts
    end

    def directory_kbar_data
      shortcuts = [ { code: "MYAX", label: "My access", path: directory_my_access_path, icon: "⭢" } ]
      # grantless members can only open their own access page; everything else 404s for them
      if directory_browsable?
        shortcuts.unshift({ code: "DRCT", label: "Directory home", path: directory_root_path, icon: "⌂" })
        shortcuts << { code: "DSRC", label: "Search", path: directory_search_path, icon: "⌕" }
      end
      if directory_admin?
        shortcuts += [
          { code: "DPPL", label: "People", path: directory_people_path, icon: "⭢" },
          { code: "DGRT", label: "Grants", path: directory_all_grants_path, icon: "⭢" },
          { code: "DAPP", label: "Apps", path: directory_apps_path, icon: "⭢" },
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

      # keep searchUrl even with no scopes, or the palette falls back to the backend endpoint
      search_scopes = directory_browsable? ? [ { key: "directory", label: "Directory", icon: "⭢" } ] : []

      { shortcuts: shortcuts, searchScopes: search_scopes, searchUrl: directory_search_kbar_path, defaultScope: (search_scopes.any? ? "directory" : nil) }
    end
    helper_method :directory_kbar_data
  end
end
