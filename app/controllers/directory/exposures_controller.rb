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

      authorize_exposure!(app, entitlement)

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

      authorize_unwire!(exposure)
      exposure.destroy!

      redirect_back fallback_location: developer_app_path(app), notice: t("directory.flash.exposure_removed")
    end

    private

    def authorize_exposure!(app, entitlement)
      unless app_owner?(app) && directory_context.can?(:expose, entitlement) && app.hq_official?
        raise Pundit::NotAuthorizedError
      end
    end

    # Unwire auth: admin can always sever an exposure (the directory
    # controls what it discloses, regardless of app owner preference).
    # Non-admins need BOTH app ownership AND the expose grant.
    #
    # This can break an app (claim disappears) but cannot open access —
    # exposures control what the token says, not who can log in.
    # Requirements (which gate login) use the same AND pattern.
    def authorize_unwire!(exposure)
      return if directory_context.admin?
      unless app_owner?(exposure.app) && directory_context.can?(:expose, exposure.entitlement)
        raise Pundit::NotAuthorizedError
      end
    end
  end
end
