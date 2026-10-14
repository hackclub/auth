module API
  module V1
    class ApplicationController < ActionController::API
      include RendersJsonErrors

      prepend_view_path "app/views/api/v1"

      helper_method :current_identity, :current_program, :current_scopes, :acting_as_program, :identity_authorized_for_scope?

      attr_reader :current_identity
      attr_reader :current_program
      attr_reader :current_scopes
      attr_reader :acting_as_program

      before_action :authenticate!

      include ActionController::HttpAuthentication::Token::ControllerMethods

      def identity_authorized_for_scope?(identity, scope)
        if current_identity
          @current_token.scopes.include?(scope)
        else
          identity.access_tokens.to_a.any? { |t| t.active? && t.application_id == current_program.id && t.scopes.include?(scope) }
        end
      end

      private

      def authenticate!
        @current_token = authenticate_with_http_token do |t, _options|
          OAuthToken.find_by(token: t) || Program.find_by(program_key: t)
        end
        unless @current_token&.active?
          return render_invalid_auth
        end
        if @current_token.is_a?(OAuthToken)
          @current_identity = @current_token.resource_owner
          @current_program = @current_token.application
          @current_scopes = @current_token.scopes
          unless @current_program&.active?
            render_invalid_auth(message: "The application this token belongs to is no longer active.")
          end
        else
          unless @current_token.hq_official?
            return render_api_error(:not_authorized,
                                    message: "Program keys are only accepted from HQ-official programs.")
          end
          @acting_as_program = true
          @current_program = @current_token
          @current_scopes = @current_program.scopes
        end
      end

      def render_invalid_auth(message: nil)
        render_api_error :invalid_auth, message: message
      end
    end
  end
end
