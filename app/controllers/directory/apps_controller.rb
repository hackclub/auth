# frozen_string_literal: true

module Directory
  # Wiring and session revokers for any app, for directory admins who can't (and shouldn't)
  # open the developer app page with its credentials.
  class AppsController < BaseController
    include DirectoryAppAuthorization
    helper_method :can_manage_app_wiring?, :can_wire_any_entitlement?, :wireable_entitlements, :entitlement_description_visible?

    def index
      authorize_visible! :directory, :admin?
      add_breadcrumb t("directory.apps.title")

      @apps = Program.official
        .or(Program.where(id: Directory::Exposure.select(:app_id)))
        .or(Program.where(id: Directory::AppRequirement.select(:app_id)))
        .or(Program.where(id: Directory::AppRevoker.select(:app_id)))
        .order(:name)
      @exposure_counts = Directory::Exposure.reaching.group(:app_id).count
      @requirement_counts = Directory::AppRequirement.group(:app_id).count
      @revokers = Directory::AppRevoker.where(app_id: @apps.select(:id)).index_by(&:app_id)
    end

    def show
      authorize_visible! :directory, :admin?
      @app = Program.find(params[:id])
      add_breadcrumb t("directory.apps.title"), directory_apps_path
      add_breadcrumb @app.name
    end
  end
end
