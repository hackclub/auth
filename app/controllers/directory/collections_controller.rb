# frozen_string_literal: true

require "csv"

module Directory
  class CollectionsController < BaseController
    before_action :set_collection, only: %i[show edit update destroy activity export]

    def index
      @collections = policy_scope(Directory::Collection)
        .select(
          "directory_collections.*",
          "(SELECT COUNT(*) FROM directory_memberships WHERE directory_memberships.collection_id = directory_collections.id) AS preloaded_direct_count",
          "(SELECT COUNT(*) FROM directory_effective_memberships WHERE directory_effective_memberships.collection_id = directory_collections.id) AS preloaded_effective_count",
          "(SELECT COUNT(*) FROM directory_exposures WHERE directory_exposures.entitlement_id = directory_collections.id) AS preloaded_exposure_count"
        )
        .order(:name)
      authorize Directory::Collection
    end

    def show
      authorize @collection
      add_breadcrumb @collection.name, directory_collection_path(@collection.slug)

      @direct_people_memberships = @collection.member_people_memberships
        .includes({ member_person: :identity }, :created_by)
        .order("identities.first_name")
        .page(params[:page]).per(100)

      @direct_group_memberships = @collection.member_group_memberships
        .includes(:member_group, :created_by)
        .order("directory_collections.name")

      direct_person_ids = @collection.member_people_memberships.select(:member_person_id)
      effective_people = @collection.effective_people
        .where.not(id: direct_person_ids)
        .includes(:identity)
        .order("identities.first_name")
        .page(params[:effective_page]).per(100)

      direct_group_ids = @collection.member_group_memberships.pluck(:member_group_id)
      effective_person_ids = effective_people.map(&:id)

      via_map = {}
      if effective_person_ids.any? && direct_group_ids.any?
        Directory::EffectiveMembership
          .where(person_id: effective_person_ids, collection_id: direct_group_ids)
          .includes(:collection)
          .each do |em|
            (via_map[em.person_id] ||= []) << em.collection
          end
      end

      ctx = pundit_user

      @effective_people_paginated = effective_people
      @effective_people_with_paths = effective_people.map do |person|
        via_groups = (via_map[person.id] || []).uniq.select do |c|
          ctx.can_any?(%w[view manage_members expose], c)
        end
        { person: person, via: via_groups }
      end

      @grants = @collection.grants_as_target
        .includes(:grantee_group, :created_by)

      if @collection.group?
        @all_memberships = @collection.memberships
          .includes(:member_person, :member_group, :created_by)
          .order(:created_at)
          .page(params[:page]).per(100)
      end

      if @collection.entitlement?
        @wired_exposures = Directory::Exposure.where(entitlement_id: @collection.id).includes(:app, :created_by)
      end

      @recent_activities = PublicActivity::Activity
        .where(trackable: @collection)
        .order(created_at: :desc)
        .limit(5)

      @consequences = if policy(@collection).manage_members? && Directory::Closure.where(descendant_id: @collection.id).where.not(ancestor_id: @collection.id).exists?
        Directory::Consequence.batch_removal_summaries(
          memberships: @direct_people_memberships.to_a, collection: @collection
        )
      else
        {}
      end
    end

    def new
      @collection = Directory::Collection.new
      authorize @collection
      add_breadcrumb t("directory.collections.new.title")
    end

    def create
      @collection = Directory::Collection.new(collection_params_for_create)
      @collection.created_by_identity_id = current_identity.id
      authorize @collection

      if @collection.valid?
        Directory.mutate!(cause: Directory.cause("collection_created", actor: current_identity.id)) { @collection.save! }
        redirect_to directory_collection_path(@collection), notice: t("directory.collections.created")
      else
        add_breadcrumb t("directory.collections.new.heading")
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @collection
      add_breadcrumb @collection.name, directory_collection_path(@collection.slug)
      add_breadcrumb t("directory.collections.edit.heading", name: @collection.name)
    end

    def update
      authorize @collection

      @collection.assign_attributes(collection_params_for_update)

      saved = if @collection.protected_changed?
        @collection.valid? && Directory.mutate!(cause: Directory.cause("collection_updated", target: @collection.id, actor: current_identity.id)) { @collection.save! }
      else
        @collection.save
      end

      if saved
        redirect_to directory_collection_path(@collection.slug), notice: t("directory.collections.updated")
      else
        add_breadcrumb @collection.name, directory_collection_path(@collection.slug)
        add_breadcrumb t("directory.collections.edit.title")
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @collection

      if @collection.confirm_destroy && params[:confirm_slug] != @collection.slug
        redirect_back fallback_location: directory_collection_path(@collection.slug),
          alert: t("directory.flash.type_slug_to_confirm")
        return
      end

      # Capture revocation data BEFORE destroy wipes effective_memberships
      revocations = []
      if @collection.entitlement?
        app_ids = @collection.affected_app_ids

        if app_ids.any?
          @collection.effective_people.each do |person|
            revocations << { identity_id: person.identity_id, email: person.primary_email, app_ids: app_ids }
          end
        end
      end

      Directory.mutate!(cause: Directory.cause("collection_deleted", target: @collection.id, actor: current_identity.id)) do
        @collection.destroy!
      end

      # Enqueue revocations directly since the rebuild diff won't find them
      if revocations.any?
        Directory::AfterChangeJob.perform_later(change_ids: [], revocations: revocations)
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

      direct_person_ids = @collection.member_people_memberships.pluck(:member_person_id).to_set
      filename = "#{@collection.slug}-members-#{Date.current.iso8601}.csv"

      headers["Content-Disposition"] = "attachment; filename=\"#{filename}\""
      headers["Content-Type"] = "text/csv; charset=utf-8"
      headers["Cache-Control"] = "no-cache"
      # SafeCsv: names and emails are user-controlled, and this file gets opened in a spreadsheet.
      self.response_body = Enumerator.new do |yielder|
        yielder << SafeCsv.generate_line([
          t("directory.export.name"),
          t("directory.export.email"),
          t("directory.export.membership_type")
        ])

        @collection.effective_memberships
          .includes(person: :identity)
          .order("identities.first_name")
          .find_each(batch_size: 500) do |em|
            person = em.person
            membership_type = direct_person_ids.include?(person.id) ? "direct" : "via"
            yielder << SafeCsv.generate_line([ person.full_name, person.primary_email, membership_type ])
          end
      end
    end

    private

    def set_collection
      @collection = Directory::Collection.find_by!(slug: params[:slug])
    end

    def collection_params_for_create
      params.require(:collection).permit(:name, :slug, :kind, :description, :protected, :confirm_destroy)
    end

    def collection_params_for_update
      params.require(:collection).permit(:name, :description, :protected, :confirm_destroy)
    end
  end
end
