# frozen_string_literal: true

module Directory
  class ViewAsController < BaseController
    def show
      authorize :directory, :admin?
      add_breadcrumb "view as"

      return unless params[:person_id].present?

      @target_person = Directory::Person.find(params[:person_id])

      target_admin = @target_person.identity.backend_user&.directory_services_admin?

      if target_admin
        @visible_collections = Directory::Collection.order(:name)
      else
        grant_ids = Directory::EffectiveGrant.where(person_id: @target_person.id).select(:target_collection_id)
        @visible_collections = Directory::Collection.where(id: grant_ids).order(:name)
      end

      direct_collection_ids = @target_person.memberships.pluck(:collection_id).to_set

      @memberships = @target_person.effective_memberships.includes(:collection).order("directory_collections.name").map do |em|
        {
          collection: em.collection,
          direct: direct_collection_ids.include?(em.collection_id),
          via_path: []
        }
      end

      @grants = Directory::EffectiveGrant.where(person_id: @target_person.id)
        .includes(:target_collection)
        .order(:permission)
    end
  end
end
