module API
  module V1
    class HealthCheckController < ApplicationController
      skip_before_action :authenticate!
      def show
        _ = Identity.last
        render json: { message: "we're chillin'" }
      end
    end
  end
end
