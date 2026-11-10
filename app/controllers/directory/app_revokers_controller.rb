# frozen_string_literal: true

module Directory
  # Session revokers live on the developer app page, so like exposures this sits outside
  # Directory::BaseController. Directory admins only: a revoker holds credentials for
  # someone else's infrastructure.
  class AppRevokersController < ::ApplicationController
    include DirectoryAppAuthorization

    before_action :authenticate_identity!
    before_action :set_app
    before_action :require_directory_admin!

    rescue_from Pundit::NotAuthorizedError do
      redirect_back fallback_location: root_path, alert: t("directory.flash.not_authorized")
    end

    def create
      return update if Directory::AppRevoker.exists?(app_id: @app.id)

      save(Directory::AppRevoker.new(app: @app), :session_revoker_added)
    end

    def update
      save(revoker!, :session_revoker_changed)
    end

    def destroy
      adapter = revoker!.adapter
      revoker!.destroy!
      @app.create_activity :session_revoker_removed, owner: current_identity, parameters: { adapter: adapter }
      redirect_to wiring_return_path(@app), notice: t("directory.flash.revoker_removed")
    end

    private

    def set_app = @app = Program.find(params[:developer_app_id])

    def require_directory_admin!
      raise Pundit::NotAuthorizedError unless directory_context.admin?
    end

    def revoker! = @revoker ||= Directory::AppRevoker.find_by!(app_id: @app.id)

    def save(revoker, activity_key)
      revoker_params = params.require(:revoker).permit(:adapter, :enabled, fields: {})
      revoker.assign_settings(adapter: revoker_params[:adapter].to_s, fields: revoker_params[:fields] || {})
      revoker.enabled = ActiveModel::Type::Boolean.new.cast(revoker_params[:enabled]) if revoker_params.key?(:enabled)

      if revoker.save
        @app.create_activity activity_key, owner: current_identity,
          parameters: { adapter: revoker.adapter, enabled: revoker.enabled }
        redirect_to wiring_return_path(@app), notice: t("directory.flash.revoker_saved")
      else
        redirect_to wiring_return_path(@app), alert: revoker.errors.full_messages.to_sentence
      end
    end
  end
end
