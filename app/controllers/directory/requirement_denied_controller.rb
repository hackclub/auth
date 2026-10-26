# frozen_string_literal: true

module Directory
  class RequirementDeniedController < ::ApplicationController
    layout "minimal"

    def show
      @app_name = params[:app]
    end
  end
end
