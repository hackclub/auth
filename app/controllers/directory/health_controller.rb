# frozen_string_literal: true

module Directory
  class HealthController < BaseController
    def show
      authorize :directory, :admin?
      add_breadcrumb t("directory.health.title")

      cached = Rails.cache.read("directory:last_validate_result")
      if cached
        @result = cached
        @validated_at = cached.try(:validated_at)
      end
    end

    def validate
      authorize :directory, :admin?

      result = Directory::Validate.call
      Rails.cache.write("directory:last_validate_result", result, expires_in: 1.hour)

      if result.valid?
        redirect_to directory_health_path, notice: t("directory.health.valid")
      else
        redirect_to directory_health_path, alert: t("directory.health.invalid", count: result.mismatches.size)
      end
    end
  end
end
