# frozen_string_literal: true

module Directory
  # not a Directory::BaseController: this lives on the developer app page, and app
  # owners there needn't be directory people.
  class ExposuresController < ::ApplicationController
    include DirectoryAppAuthorization
    rescue_from Pundit::NotAuthorizedError do
      redirect_back fallback_location: root_path, alert: t("directory.flash.not_authorized")
    end
    before_action :authenticate_identity!

    def create
      app = Program.find(params[:app_id])
      entitlement = find_visible_entitlement!(params[:entitlement_slug])

      authorize_app_entitlement_wiring!(app, entitlement)

      Directory::Exposure.create!(
        app: app,
        entitlement: entitlement,
        claim_name: params[:claim_name].presence,
        created_by_identity_id: current_identity.id
      )

      if params[:also_require] == "1"
        Directory::AppRequirement.find_or_create_by!(app: app, entitlement: entitlement)
      end

      redirect_to wiring_return_path(app), notice: t("directory.flash.exposure_added")
    rescue ActiveRecord::RecordInvalid => e
      redirect_to wiring_return_path(app), alert: e.record.errors.full_messages.to_sentence
    rescue ActiveRecord::RecordNotUnique
      redirect_to wiring_return_path(app), alert: t("directory.flash.already_wired")
    end

    def destroy
      exposure = Directory::Exposure.find(params[:id])
      app = exposure.app
      # an exposure of an entitlement you can't see answers like a missing id
      raise ActiveRecord::RecordNotFound unless entitlement_visible?(exposure.entitlement)

      authorize_app_entitlement_unwiring!(app, exposure.entitlement)
      exposure.destroy!

      redirect_to wiring_return_path(app), notice: t("directory.flash.exposure_removed")
    end
  end
end
