# frozen_string_literal: true

module Directory
  class ViewAsController < BaseController
    def show
      authorize :directory, :admin?
      add_breadcrumb "view as"

      person_id_param = params[:person_id_id].presence || params[:person_id]
      return unless person_id_param.present?

      @target_person = Directory::Person.find_by_public_id(person_id_param) ||
        Directory::Person.joins(:identity).find_by("lower(identities.primary_email) = ?", person_id_param.to_s.strip.downcase)
      return unless @target_person

      target_admin = @target_person.identity.backend_user&.directory_services_admin?

      if target_admin
        @visible_collections = Directory::Collection.order(:name)
      else
        grant_ids = Directory::EffectiveGrant.where(person_id: @target_person.id).select(:target_collection_id)
        @visible_collections = Directory::Collection.where(id: grant_ids).order(:name)
      end

      @memberships = @target_person.memberships_with_via_path

      @grants = Directory::EffectiveGrant.where(person_id: @target_person.id)
        .includes(:target_collection)
        .order(:permission)
    end
  end
end
