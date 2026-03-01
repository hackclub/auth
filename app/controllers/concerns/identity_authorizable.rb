# frozen_string_literal: true

# Opt-in concern for frontend controllers that want Pundit authorization
# with Identity as the authorization subject (instead of Backend::User).
#
# This does NOT affect backend controllers — they continue using
# Backend::User via Backend::ApplicationController.
module IdentityAuthorizable
  extend ActiveSupport::Concern

  included do
    include Pundit::Authorization
    after_action :verify_authorized

    rescue_from Pundit::NotAuthorizedError do |_e|
      flash[:error] = "You're not authorized to do that."
      redirect_to root_path
    end

    def pundit_user
      current_identity
    end
  end
end
