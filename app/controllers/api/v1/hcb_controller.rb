module API
  module V1
    class HCBController < ApplicationController
      skip_before_action :authenticate!

      def show
        render json: { pending: Verification.where(status: "pending").count }
      end
    end
  end
end
