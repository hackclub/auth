# frozen_string_literal: true

module Directory
  class GrantsController < BaseController
    def index
      authorize Directory::Grant
      add_breadcrumb t("directory.grants.index.title")

      @grants = Directory::Grant
        .includes(:grantee_group, :target_collection, :created_by)
        .order(:created_at)
    end

    def create
      @collection = Directory::Collection.find_by!(slug: params[:collection_slug])
      grant = @collection.grants_as_target.new(grant_params)
      grant.created_by_identity_id = current_identity.id
      authorize grant

      ActiveRecord::Base.transaction do
        grant.save!
        Directory::Rebuild.call(cause: "grant_created:#{grant.id}")
      end

      redirect_back fallback_location: directory_collection_path(@collection.slug),
        notice: t("directory.grants.created")
    rescue ActiveRecord::RecordInvalid => e
      redirect_back fallback_location: directory_collection_path(@collection.slug),
        alert: e.record.errors.full_messages.to_sentence
    end

    def destroy
      grant = Directory::Grant.find(params[:id])
      @collection = grant.target_collection
      authorize grant

      ActiveRecord::Base.transaction do
        grant.destroy!
        Directory::Rebuild.call(cause: "grant_deleted:#{grant.id}")
      end

      redirect_back fallback_location: directory_collection_path(@collection.slug),
        notice: t("directory.grants.destroyed")
    end

    private

    def grant_params
      params.require(:grant).permit(:grantee_group_id, :permission, :recursive)
    end
  end
end
