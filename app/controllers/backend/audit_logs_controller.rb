module Backend
  class AuditLogsController < ApplicationController
    skip_after_action :verify_authorized

    hint :back_navigation, on: :index
    def index
      set_keyboard_shortcut(:back, backend_root_path)
      
      scope = PublicActivity::Activity.order(created_at: :desc)

      if params[:admin_actions_only]
        scope = scope.where(owner_type: "Backend::User")
      else
        scope = scope.where(owner_type: "Backend::User")
      end

      @activities = scope.page(params[:page]).per(50)
    end
  end
end
