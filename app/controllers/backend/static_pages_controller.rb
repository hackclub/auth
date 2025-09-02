module Backend
  class StaticPagesController < ApplicationController
    skip_before_action :authenticate_user!, only: [ :login ]
    skip_after_action :verify_authorized

    def index
      if current_user&.manual_document_verifier? || current_user&.super_admin?
        @pending_verifications_count = Verification.where(status: "pending").count
      end
    end

    def login
    end

    def session_dump
      raise "can't do that!" if Rails.env.production?
    end
  end
end
