module Backend
  class StaticPagesController < ApplicationController
    skip_after_action :verify_authorized

    hint :list_navigation, on: :index

    def index
      if current_user&.manual_document_verifier? || current_user&.super_admin?
        @pending_verifications_count = Verification.where(status: "pending").count
      end
    end

    def session_dump
      raise "can't do that!" if Rails.env.production?
    end

    def flash_test
      raise "nope" if Rails.env.production?
      flash[:success] = "this is a success flash"
      flash[:notice] = "this is a notice flash"
      flash[:info] = "this is an info flash"
      flash[:warning] = "this is a warning flash"
      flash[:alert] = "this is an alert flash"
      flash[:error] = "this is an error flash"
      flash[:danger] = "this is a danger flash"
      redirect_to backend_root_path
    end
  end
end
