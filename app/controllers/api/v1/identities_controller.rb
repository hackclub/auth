module API
  module V1
    class IdentitiesController < ApplicationController
      def me
        @identity = current_identity
        raise ActiveRecord::RecordNotFound unless current_identity
        render :me
      end

      def show
        raise Pundit::NotAuthorizedError unless acting_as_program
        @identity = ident_scope.find_by_public_id!(params[:id])
        render :show
      end

      def set_slack_id
        raise Pundit::NotAuthorizedError unless acting_as_program && current_scopes.include?("set_slack_id")
        @identity = ident_scope.find_by_public_id!(params[:id])

        if @identity.slack_id.present?
          return render json: { message: "slack already associated?" }
        end

        @identity.update!(slack_id: params.require(:slack_id))
        @identity.create_activity(key: "identity.set_slack_id", owner: current_program)
        render :show
      end

      def index
        raise Pundit::NotAuthorizedError unless acting_as_program
        @identities = ident_scope.all
        render :index
      end

      private

      def ident_scope
        current_program.identities
      end
    end
  end
end
