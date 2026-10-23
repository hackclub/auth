# frozen_string_literal: true

module Directory
  class ActivityController < BaseController
    TRACKABLE_TYPES = %w[
      Directory::Collection
      Directory::Person
      Directory::Membership
      Directory::Grant
    ].freeze

    def index
      authorize :directory, :admin?
      add_breadcrumb t("directory.activity.title")

      @activities = PublicActivity::Activity
        .where(trackable_type: TRACKABLE_TYPES)
        .order(created_at: :desc)
        .page(params[:page])
        .per(50)
    end
  end
end
