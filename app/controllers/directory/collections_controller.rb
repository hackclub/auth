# frozen_string_literal: true

require "csv"

module Directory
  class CollectionsController < BaseController
    before_action :set_collection, only: %i[show edit update destroy activity export]

    def index
      @collections = policy_scope(Directory::Collection).order(:name)
      authorize Directory::Collection
    end

    def show
      authorize @collection
      add_breadcrumb @collection.name, directory_collection_path(@collection.slug)

      @direct_people_memberships = @collection.member_people_memberships
        .includes({ member_person: :identity }, :created_by)
        .order("identities.first_name")

      @direct_group_memberships = @collection.member_group_memberships
        .includes(:member_group, :created_by)
        .order("directory_collections.name")

      direct_person_ids = @collection.member_people_memberships.select(:member_person_id)
      @effective_people = @collection.effective_people
        .where.not(id: direct_person_ids)
        .includes(:identity)
        .order("identities.first_name")

      @grants = @collection.grants_as_target
        .includes(:grantee_group, :created_by)

      @recent_activities = PublicActivity::Activity
        .where(trackable: @collection)
        .order(created_at: :desc)
        .limit(5)

      # Precompute consequence text for each person membership's remove confirm
      @consequences = {}
      person_memberships = @direct_people_memberships.to_a
      person_memberships += @collection.memberships.includes({ member_person: :identity }).where.not(member_person_id: nil).to_a if @collection.group?
      person_memberships.uniq(&:id).each do |m|
        next unless m.member_person
        summary = Directory::Consequence.removal_summary(person: m.member_person, collection: @collection)
        @consequences[m.id] = summary if summary
      end
    end

    def new
      @collection = Directory::Collection.new
      authorize @collection
      add_breadcrumb t("directory.collections.new.title")
    end

    def create
      klass = case params.dig(:collection, :kind)
              when "entitlement" then Directory::Entitlement
              else Directory::Group
              end
      @collection = klass.new(collection_params_for_create.except(:kind))
      @collection.created_by_identity_id = current_identity.id
      authorize @collection

      if @collection.save
        redirect_to directory_collection_path(@collection.slug), notice: "collection created."
      else
        add_breadcrumb "new collection"
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @collection
      add_breadcrumb @collection.name, directory_collection_path(@collection.slug)
      add_breadcrumb t("directory.collections.edit.title")
    end

    def update
      authorize @collection

      if @collection.update(collection_params_for_update)
        redirect_to directory_collection_path(@collection.slug), notice: t("directory.collections.updated")
      else
        add_breadcrumb @collection.name, directory_collection_path(@collection.slug)
        add_breadcrumb t("directory.collections.edit.title")
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @collection

      if @collection.protected && params[:confirm_slug] != @collection.slug
        redirect_back fallback_location: directory_collection_path(@collection.slug),
          alert: "type the collection slug to confirm deletion."
        return
      end

      ActiveRecord::Base.transaction do
        @collection.destroy!
        Directory::Rebuild.call(cause: "collection_deleted:#{@collection.id}")
      end

      redirect_to directory_root_path, notice: t("directory.collections.destroyed")
    end

    def activity
      authorize @collection, :show?
      add_breadcrumb @collection.name, directory_collection_path(@collection.slug)
      add_breadcrumb t("directory.collections.activity.title")

      @activities = PublicActivity::Activity
        .where(trackable: @collection)
        .order(created_at: :desc)
        .page(params[:page])
        .per(50)
    end

    def export
      authorize @collection, :show?

      effective = @collection.effective_memberships
        .includes(person: :identity)
        .order("identities.first_name")

      direct_person_ids = @collection.member_people_memberships.pluck(:member_person_id).to_set

      csv_data = CSV.generate do |csv|
        csv << [
          t("directory.export.name"),
          t("directory.export.email"),
          t("directory.export.membership_type")
        ]

        effective.each do |em|
          person = em.person
          membership_type = direct_person_ids.include?(person.id) ? "direct" : "via"
          csv << [person.full_name, person.primary_email, membership_type]
        end
      end

      send_data csv_data,
        filename: "#{@collection.slug}-members-#{Date.current.iso8601}.csv",
        type: "text/csv; charset=utf-8",
        disposition: "attachment"
    end

    private

    def set_collection
      @collection = Directory::Collection.find_by!(slug: params[:slug])
    end

    def collection_params_for_create
      params.require(:collection).permit(:name, :slug, :kind, :description, :protected)
    end

    def collection_params_for_update
      params.require(:collection).permit(:name, :description, :protected)
    end
  end
end
