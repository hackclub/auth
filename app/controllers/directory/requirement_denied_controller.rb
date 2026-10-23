# frozen_string_literal: true

module Directory
  class RequirementDeniedController < BaseController
    skip_before_action :ensure_directory_access!

    def show
      @app_name = params[:app]
    end

    private

    def skip_authorization? = true
  end
end
