# frozen_string_literal: true

module Directory
  class HealthController < BaseController
    def show
      authorize :directory, :admin?
      add_breadcrumb "health"

      cached = Rails.cache.read("directory:validate_result")
      if cached
        @result = cached[:result]
        @validated_at = cached[:at]
      end

      @revokers = Directory::AppRevoker.includes(:app).order(:app_id)
    end

    def validate
      authorize :directory, :admin?

      result = Directory::Validate.call
      Rails.cache.write("directory:validate_result", { result: result, at: Time.current })

      if result.valid?
        redirect_to directory_health_path, notice: "valid — no drift detected."
      else
        redirect_to directory_health_path, alert: "drift detected!"
      end
    end
  end
end
