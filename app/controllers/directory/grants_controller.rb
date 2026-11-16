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
      @collection = find_visible_collection!(params[:collection_slug])
      authorize Directory::Grant

      grantee = Directory::Collection.groups.find_by!(slug: params[:grantee_group_slug]&.strip)

      # re-adding an existing grant can only turn recursion on: the box is unticked by
      # default, so reading "unticked" as "off" would silently strip it
      grant = @collection.grants_as_target.find_or_initialize_by(grantee_group: grantee, permission: params[:permission])
      updating = grant.persisted?
      if updating && (grant.recursive || params[:recursive] != "1")
        redirect_back fallback_location: directory_collection_path(@collection.slug),
          alert: t("directory.flash.grant_already_exists")
        return
      end

      grant.recursive = params[:recursive] == "1"
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
