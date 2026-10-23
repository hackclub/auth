# frozen_string_literal: true

module Directory
  class MyAccessController < BaseController
    def show
      skip_authorization
      add_breadcrumb t("directory.my_access.title")

      @person = current_directory_person

      unless @person
        render "not_in_directory"
        return
      end

      all_effective = @person.effective_memberships
        .includes(:collection)
        .order("directory_collections.name")

      direct_collection_ids = @person.memberships.pluck(:collection_id).to_set

      @direct_memberships = all_effective.select { |em| direct_collection_ids.include?(em.collection_id) }
      @via_memberships = all_effective.reject { |em| direct_collection_ids.include?(em.collection_id) }
      @apps_told_about = []
    end

    private

    def skip_authorization?
      action_name == "show"
    end
  end
end
