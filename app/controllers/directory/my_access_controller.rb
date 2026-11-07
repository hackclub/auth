# frozen_string_literal: true

module Directory
  class MyAccessController < BaseController
    def show
      skip_authorization
      add_breadcrumb t("directory.my_access.show.title")

      @person = current_directory_person

      unless @person
        render "not_in_directory"
        return
      end

      @memberships = @person.memberships_with_via_path

      # App access: which apps this person can reach via entitlements
      entitlement_ids = @person.effective_memberships
        .joins(:collection)
        .where(directory_collections: { kind: "entitlement" })
        .pluck(:collection_id)
      @app_exposures = if entitlement_ids.any?
        Directory::Exposure.includes(:app, :entitlement)
          .where(entitlement_id: entitlement_ids)
          .group_by { |e| e.app }
      else
        {}
      end
    end

    private

    def skip_authorization?
      action_name == "show"
    end
  end
end
