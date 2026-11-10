# frozen_string_literal: true

module Directory
  # not a Directory::BaseController: this lives on the developer app page, and app
  # owners there needn't be directory people.
  class AppRequirementsController < ::ApplicationController
    include DirectoryAppAuthorization
    rescue_from Pundit::NotAuthorizedError do
      redirect_back fallback_location: root_path, alert: t("directory.flash.not_authorized")
    end
    before_action :authenticate_identity!

    def create
      app = Program.find(params[:app_id])
      entitlement = Directory::Collection.entitlements.find_by!(slug: params[:entitlement_slug])

      authorize_app_entitlement_wiring!(app, entitlement)

      Directory::AppRequirement.create!(app: app, entitlement: entitlement)
      log_requirement(:requirement_added, app, entitlement)
      revoke_tokens_for_non_members(app, entitlement)

      redirect_back fallback_location: developer_app_path(app), notice: t("directory.flash.requirement_added")
    rescue ActiveRecord::RecordInvalid => e
      redirect_back fallback_location: developer_app_path(app), alert: e.record.errors.full_messages.to_sentence
    rescue ActiveRecord::RecordNotUnique
      redirect_back fallback_location: developer_app_path(app), alert: t("directory.flash.requirement_already_exists")
    end

    def destroy
      app = Program.find(params[:app_id])
      entitlement = Directory::Collection.find_by!(slug: params[:id])
      req = Directory::AppRequirement.find_by!(app_id: app.id, entitlement_id: entitlement.id)

      authorize_app_entitlement_unwiring!(app, entitlement)
      req.destroy!
      log_requirement(:requirement_removed, app, entitlement)

      # dropping the last requirement opens the app, so there's nobody to revoke
      revoke_tokens_for_non_members(app, entitlement) if Directory::AppRequirement.exists?(app_id: app.id)

      redirect_back fallback_location: developer_app_path(app), notice: t("directory.flash.requirement_removed")
    end

    private

    # on the app, for its developer activity log, and on the entitlement, for the directory's
    def log_requirement(key, app, entitlement)
      params = { app_name: app.name, entitlement_name: entitlement.name, entitlement_slug: entitlement.slug }
      app.create_activity key, owner: current_identity, parameters: params
      entitlement.create_activity key, owner: current_identity, params: params
    end

    def revoke_tokens_for_non_members(app, _entitlement)
      Directory::RevokeAccess.bulk_revoke_non_passing(app: app)
    end
  end
end
