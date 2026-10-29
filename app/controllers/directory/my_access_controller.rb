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
        if direct_collection_ids.include?(em.collection_id)
          { collection: em.collection, direct: true, via_path: [] }
        else
          # find a direct collection that reaches this one through the closure
          via = find_via_path(direct_collection_ids, em.collection_id)
          { collection: em.collection, direct: false, via_path: via }
        end
      end
    end

    private

    def skip_authorization?
      action_name == "show"
    end

    # Walk the closure to find a path from any of the person's direct collections
    # to the target ancestor collection. Returns an array of Collection objects.
    def find_via_path(direct_collection_ids, ancestor_id)
      link = Directory::Closure.where(ancestor_id: ancestor_id)
        .where(descendant_id: direct_collection_ids.to_a)
        .where.not(descendant_id: ancestor_id)
        .order(:depth)
        .first
      return [] unless link

      child = Directory::Collection.find_by(id: link.descendant_id)
      child ? [ child ] : []
    end
  end
end
