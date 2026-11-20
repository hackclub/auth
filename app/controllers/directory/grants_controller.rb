# frozen_string_literal: true

module Directory
  class GrantsController < BaseController
    def index
      authorize Directory::Grant
      add_breadcrumb t("directory.grants.index.title")

      @grants = Directory::Grant
        .includes(:grantee_group, :grantee_person, :target_collection, :created_by)
        .order(:created_at)
        .page(params[:page]).per(50)
    end

    def create
      @collection = find_visible_collection!(params[:collection_slug])
      authorize Directory::Grant

      # the picker sets grantee_group_slug to the display text (slug or email) and
      # grantee_group_slug_id to the public ID (dcol!xxx or dper!xxx). prefer the ID.
      grantee_id = params[:grantee_group_slug_id]&.strip.presence || params[:grantee_group_slug]&.strip
      grant_attrs = { permission: params[:permission] }

      if grantee_id&.start_with?("dper!")
        person = Directory::Person.find_by_public_id(grantee_id)
        raise ActiveRecord::RecordNotFound, "person not found" unless person
        grant_attrs[:grantee_person] = person
      elsif grantee_id&.start_with?("dcol!")
        grantee = Directory::Collection.groups.find_by_public_id!(grantee_id)
        grant_attrs[:grantee_group] = grantee
      else
        grantee = Directory::Collection.groups.find_by!(slug: grantee_id)
        grant_attrs[:grantee_group] = grantee
      end

      grant = @collection.grants_as_target.find_or_initialize_by(grant_attrs)
      updating = grant.persisted?
      if updating && (grant.recursive || params[:recursive] != "1")
        redirect_back fallback_location: directory_collection_path(@collection.slug),
          alert: t("directory.flash.grant_already_exists")
        return
      end

      grant.recursive = params[:recursive] == "1" if grant.grantee_group_id.present?
      grant.created_by_identity_id ||= current_identity.id
      cause = updating ? "grant_updated" : "grant_created"
      Directory.mutate!(cause: Directory.cause(cause, actor: current_identity.id)) { grant.save! }

      redirect_back fallback_location: directory_collection_path(@collection.slug),
        notice: t(updating ? "directory.flash.grant_updated" : "directory.flash.grant_added")
    rescue ActiveRecord::RecordNotFound
      missing_collection! unless @collection
      redirect_back fallback_location: collection_fallback_path, alert: t("directory.flash.grantee_not_found")
    rescue ActiveRecord::RecordInvalid => e
      redirect_back fallback_location: collection_fallback_path, alert: e.record.errors.full_messages.to_sentence
    rescue ActiveRecord::RecordNotUnique
      redirect_back fallback_location: collection_fallback_path, alert: t("directory.flash.grant_already_exists")
    end

    def update
      grant = Directory::Grant.find(params[:id])
      raise ActiveRecord::RecordNotFound unless directory_admin? || collection_visible?(grant.target_collection)

      @collection = grant.target_collection
      authorize grant

      grant.recursive = ActiveModel::Type::Boolean.new.cast(params[:recursive]) || false
      if grant.recursive_changed?
        Directory.mutate!(cause: Directory.cause("grant_updated", target: grant.id, actor: current_identity.id)) { grant.save! }
      end

      redirect_back fallback_location: directory_collection_path(@collection.slug),
        notice: t("directory.flash.grant_updated")
    rescue ActiveRecord::RecordInvalid => e
      redirect_back fallback_location: directory_collection_path(@collection.slug), alert: e.record.errors.full_messages.to_sentence
    end

    def destroy
      grant = Directory::Grant.find(params[:id])
      raise ActiveRecord::RecordNotFound unless directory_admin? || collection_visible?(grant.target_collection)

      @collection = grant.target_collection
      authorize grant

      Directory.mutate!(cause: Directory.cause("grant_removed", target: grant.id, actor: current_identity.id)) { grant.destroy! }

      redirect_back fallback_location: directory_collection_path(@collection.slug),
        notice: t("directory.flash.grant_removed")
    end

    private

    def collection_fallback_path
      @collection ? directory_collection_path(@collection.slug) : directory_root_path
    end

    # admins get a flash (people/show builds this URL from whatever they typed); everyone
    # else gets a 404, the same as a slug they can't see (find_visible_collection!).
    def missing_collection!
      raise ActiveRecord::RecordNotFound unless directory_admin?

      skip_authorization
    end
  end
end
