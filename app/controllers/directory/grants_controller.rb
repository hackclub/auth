# frozen_string_literal: true

module Directory
  class GrantsController < BaseController
    def index
      authorize Directory::Grant
      add_breadcrumb t("directory.grants.index.title")

      @grants = Directory::Grant
        .includes(:grantee_group, :target_collection, :created_by)
        .order(:created_at)
        .page(params[:page]).per(50)
    end

    def create
      @collection = Directory::Collection.find_by!(slug: params[:collection_slug])
      authorize Directory::Grant

      grantee = Directory::Collection.groups.find_by!(slug: params[:grantee_group_slug]&.strip)

      # (grantee, target, permission) is unique, so re-adding an existing grant either
      # flips its recursive flag (the only way to change it from the UI) or is a no-op.
      grant = @collection.grants_as_target.find_or_initialize_by(grantee_group: grantee, permission: params[:permission])
      recursive = params[:recursive] == "1"
      if grant.persisted? && grant.recursive == recursive
        redirect_back fallback_location: directory_collection_path(@collection.slug),
          alert: t("directory.flash.grant_already_exists")
        return
      end

      updating = grant.persisted?
      grant.recursive = recursive
      grant.created_by_identity_id ||= current_identity.id
      cause = updating ? "grant_updated" : "grant_created"
      Directory.mutate!(cause: Directory.cause(cause, actor: current_identity.id)) { grant.save! }

      redirect_back fallback_location: directory_collection_path(@collection.slug),
        notice: t(updating ? "directory.flash.grant_updated" : "directory.flash.grant_added")
    rescue ActiveRecord::RecordNotFound
      missing_collection! unless @collection
      redirect_back fallback_location: collection_fallback_path, alert: t("directory.flash.group_not_found")
    rescue ActiveRecord::RecordInvalid => e
      redirect_back fallback_location: collection_fallback_path, alert: e.record.errors.full_messages.to_sentence
    rescue ActiveRecord::RecordNotUnique
      redirect_back fallback_location: collection_fallback_path, alert: t("directory.flash.grant_already_exists")
    end

    def destroy
      grant = Directory::Grant.find(params[:id])
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

    # The collection lookup itself failed, so nothing was authorized. Admins get a flash
    # (people/show's add-to-group form builds the URL from whatever they typed); anyone
    # else gets the plain 404 so a missing slug and a hidden one look the same.
    def missing_collection!
      raise ActiveRecord::RecordNotFound unless directory_admin?

      skip_authorization
    end
  end
end
