module Backend
  class AuditLogsController < ApplicationController
    skip_after_action :verify_authorized

    def index
      scope = PublicActivity::Activity.order(created_at: :desc)
      scope = scope.where(owner_type: "Backend::User") if params[:admin_actions_only]

      @activities = scope.page(params[:page]).per(50)
    end
  end
end
