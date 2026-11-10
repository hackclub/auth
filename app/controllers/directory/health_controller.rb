# frozen_string_literal: true

module Directory
  class HealthController < BaseController
    def show
      authorize :directory, :admin?
      load_health
    end

    # runs the check right here so the page can show the full diff, not just the summary
    def validate
      authorize :directory, :admin?
      load_health
      @result = Directory::Validate.call
      @validated_at = Time.current
      flash.now[@result.valid? ? :notice : :alert] = t(@result.valid? ? "directory.flash.health_valid" : "directory.flash.health_drift")
      render :show
    end

    private

    def load_health
      add_breadcrumb t("directory.health.show.heading")
      @last_run = Directory::ValidateJob.last_run
      @revokers = Directory::AppRevoker.includes(:app).order(:app_id)
    end
  end
end
