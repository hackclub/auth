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

      @memberships = all_effective.map do |em|
        {
          collection: em.collection,
          direct: direct_collection_ids.include?(em.collection_id),
          via_path: []
        }
      end
    end

    private

    def skip_authorization?
      action_name == "show"
    end
  end
end
