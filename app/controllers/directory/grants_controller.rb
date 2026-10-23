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
      authorize Directory::Grant

      grantee = Directory::Collection.groups.find_by!(slug: params[:grantee_group_slug].strip)

      grant = @collection.grants_as_target.new(
        grantee_group: grantee,
        permission: params[:permission],
        recursive: params[:recursive] == "1",
        created_by_identity_id: current_identity.id
      )

      ActiveRecord::Base.transaction do
        grant.save!
        Directory::Rebuild.call(cause: "grant:#{grant.id}")
      end

      redirect_back fallback_location: directory_collection_path(@collection.slug),
        notice: "grant added."
    rescue ActiveRecord::RecordNotFound => e
      redirect_back fallback_location: directory_collection_path(@collection.slug),
        alert: e.message
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
        Directory::Rebuild.call(cause: "grant_removed:#{grant.id}")
      end

      redirect_back fallback_location: directory_collection_path(@collection.slug),
        notice: "grant removed."
    end
  end
end
