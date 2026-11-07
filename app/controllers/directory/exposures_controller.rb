# frozen_string_literal: true

module Directory
  # Manages exposure wiring (telling an app about an entitlement).
  #
  # Inherits from ::ApplicationController, not Directory::BaseController,
  # because these actions live on the app page (/developer_apps/:id) and
  # must be reachable by app owners who are not directory people.
  class ExposuresController < ::ApplicationController
    include DirectoryAppAuthorization
    rescue_from Pundit::NotAuthorizedError do
      redirect_back fallback_location: root_path, alert: t("directory.flash.not_authorized")
    end
    before_action :authenticate_identity!

    def create
      app = Program.find(params[:app_id])
      entitlement = Directory::Collection.entitlements.find_by!(slug: params[:entitlement_slug])

      authorize_app_entitlement_wiring!(app, entitlement)

      Directory::Exposure.create!(
        app: app,
        entitlement: entitlement,
        claim_name: params[:claim_name],
        created_by_identity_id: current_identity.id
      )

      redirect_back fallback_location: developer_app_path(app), notice: t("directory.flash.exposure_added")
    rescue ActiveRecord::RecordInvalid => e
      redirect_back fallback_location: developer_app_path(app), alert: e.record.errors.full_messages.to_sentence
    rescue ActiveRecord::RecordNotUnique
      redirect_back fallback_location: developer_app_path(app), alert: t("directory.flash.already_wired")
    end

    def destroy
      exposure = Directory::Exposure.find(params[:id])
      app = exposure.app

      authorize_app_entitlement_unwiring!(app, exposure.entitlement)
      exposure.destroy!

      redirect_back fallback_location: developer_app_path(app), notice: t("directory.flash.exposure_removed")
    end
  end
end
