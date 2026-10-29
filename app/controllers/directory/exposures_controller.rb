# frozen_string_literal: true

module Directory
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

    def authorize_unwire!(exposure)
      return if directory_context.admin?
      unless app_owner?(exposure.app) && directory_context.can?(:expose, exposure.entitlement)
        raise Pundit::NotAuthorizedError
      end
    end

  end
end
