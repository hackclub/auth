# frozen_string_literal: true

module Directory
  # Manages login requirements (must be in entitlement X to use app Y).
  #
  # Inherits from ::ApplicationController, not Directory::BaseController,
  # because these actions live on the app page (/developer_apps/:id) and
  # must be reachable by app owners who are not directory people.
  class AppRequirementsController < ::ApplicationController
    include DirectoryAppAuthorization
    rescue_from Pundit::NotAuthorizedError do
      redirect_back fallback_location: root_path, alert: t("directory.flash.not_authorized")
    end
    before_action :authenticate_identity!

    def create
      app = Program.find(params[:app_id])
      entitlement = Directory::Collection.entitlements.find_by!(slug: params[:entitlement_slug])

      authorize_requirement!(app, entitlement)

      req = Directory::AppRequirement.create!(app: app, entitlement: entitlement)

      # §3.7: writing a requirement revokes tokens for non-members
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

      authorize_unwire!(app, entitlement)
      req.destroy!

      redirect_back fallback_location: developer_app_path(app), notice: t("directory.flash.requirement_removed")
    end

    private

    def authorize_requirement!(app, entitlement)
      ctx = directory_context
      unless app_owner?(app) && ctx.can?(:expose, entitlement) && app.hq_official?
        raise Pundit::NotAuthorizedError
      end
    end

    # Unwire auth: admin can always remove a requirement. Non-admins
    # need BOTH app ownership AND the expose grant — removing a login
    # gate opens the app to more people, so both sides must agree.
    def authorize_unwire!(app, entitlement)
      ctx = directory_context
      return if ctx.admin?
      unless app_owner?(app) && ctx.can?(:expose, entitlement)
        raise Pundit::NotAuthorizedError
      end
    end


    def revoke_tokens_for_non_members(app, _entitlement)
      Directory::RevokeAccess.bulk_revoke_non_passing(app: app)
    end
  end
end
