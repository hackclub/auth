# frozen_string_literal: true

require "csv"

module Directory
  class CollectionsController < BaseController
    EMAIL_LOOKUP_MISS_KEY = "directory_collection.email_lookup_miss"

    before_action :set_collection, only: %i[show edit update destroy activity export]

    def index
      @collections = policy_scope(Directory::Collection)
        .select(
          "directory_collections.*",
          Arel.sql(ActiveRecord::Base.sanitize_sql_array([
            "(SELECT COUNT(*) FROM directory_memberships WHERE directory_memberships.collection_id = directory_collections.id AND directory_memberships.member_person_id IS NOT NULL AND (directory_memberships.expires_at IS NULL OR directory_memberships.expires_at > ?)) AS preloaded_direct_count", Time.current
          ])),
          Arel.sql(ActiveRecord::Base.sanitize_sql_array([
            "(SELECT COUNT(*) FROM directory_effective_memberships WHERE directory_effective_memberships.collection_id = directory_collections.id AND (directory_effective_memberships.expires_at IS NULL OR directory_effective_memberships.expires_at > ?)) AS preloaded_effective_count", Time.current
          ])),
          "(SELECT COUNT(*) FROM directory_exposures WHERE directory_exposures.entitlement_id = directory_collections.id) AS preloaded_exposure_count"
        )
        .order(:name)
      authorize Directory::Collection
    end

    def show
      authorize_visible! @collection
      add_breadcrumb @collection.name, directory_collection_path(@collection.slug)

      @direct_people_memberships = @collection.member_people_memberships
        .includes({ member_person: :identity }, :created_by)
        .order("identities.first_name")
        .page(params[:page]).per(100)

      @direct_group_memberships = @collection.member_group_memberships.active
        .includes(:member_group, :created_by)
        .order("directory_collections.name")

      @row_counts = @collection.memberships
        .group(Arel.sql("member_person_id IS NOT NULL"))
        .group(@collection.memberships.sanitize_sql([ "expires_at IS NOT NULL AND expires_at <= ?", Time.current ]))
        .count
        .to_h { |(person, expired), n| [ [ person ? :people : :groups, expired ? :expired : :active ], n ] }

      active_direct_person_ids = @collection.member_people_memberships.active.select(:member_person_id)
      effective_people = @collection.effective_people
        .where.not(id: active_direct_person_ids)
        .includes(:identity)
        .order("identities.first_name")
        .page(params[:effective_page]).per(100)

      direct_group_ids = @collection.member_group_memberships.active.pluck(:member_group_id)
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
          .includes({ member_person: :identity }, :member_group, :created_by)
          .order(:created_at)
          .page(params[:members_page]).per(100)
      end

      if @collection.entitlement?
        @wired_exposures = Directory::Exposure.where(entitlement_id: @collection.id).includes(:app, :created_by)
      end

      @recent_activities = preload_activities(visible_activities.order(created_at: :desc).limit(5))

      # the rows each page renders with a remove button
      @consequences = if policy(@collection).manage_members?
        Directory::Consequence.batch_removal_summaries(
          memberships: @collection.group? ? @all_memberships.to_a : @direct_people_memberships.to_a + @direct_group_memberships.to_a,
          collection: @collection, viewer: pundit_user
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

      # before destroy wipes effective_memberships
      revocations = Directory::DestroyRevocations.for_entitlement(@collection)

      begin
        Directory.mutate!(cause: Directory.cause("collection_deleted", target: @collection.id, actor: current_identity.id)) do
          @collection.destroy!
        end
      rescue ActiveRecord::InvalidForeignKey
        redirect_to directory_collection_path(@collection.slug),
          alert: t("directory.collections.cannot_destroy_in_use")
        return
      rescue ActiveRecord::RecordNotDestroyed => e
        redirect_to directory_collection_path(@collection.slug),
          alert: e.record.errors.full_messages.to_sentence
        return
      end

      # the rebuild diff won't see people of a deleted collection
      if revocations.any?
        Directory::AfterChangeJob.perform_later(change_ids: [], revocations: revocations)
      end

      redirect_to directory_root_path, notice: t("directory.collections.destroyed")
    end

    def activity
      authorize_visible! @collection
      add_breadcrumb @collection.name, directory_collection_path(@collection.slug)
      add_breadcrumb t("directory.collections.activity.title", name: @collection.name)

      @activities = preload_activities(visible_activities
        .order(created_at: :desc)
        .page(params[:page])
        .per(50))
    end

    def export
      authorize_visible! @collection

      direct_person_ids = @collection.member_people_memberships.active.pluck(:member_person_id).to_set
      filename = "#{@collection.slug}-members-#{Date.current.iso8601}.csv"

      headers["Content-Disposition"] = "attachment; filename=\"#{filename}\""
      headers["Content-Type"] = "text/csv; charset=utf-8"
      headers["Cache-Control"] = "no-cache"
      # SafeCsv: names and emails are user-controlled, and this file gets opened in a spreadsheet.
      self.response_body = Enumerator.new do |yielder|
        yielder << SafeCsv.generate_line([
          t("directory.export.name"),
          t("directory.export.email"),
          t("directory.export.hca_id"),
          t("directory.export.membership_type")
        ])

        @collection.effective_memberships
          .includes(person: :identity)
          .order("identities.first_name")
          .each do |em|
            person = em.person
            membership_type = direct_person_ids.include?(person.id) ? "direct" : "via"
            yielder << SafeCsv.generate_line([ person.full_name, person.primary_email, person.identity.public_id, membership_type ])
          end
      end
    end

    private

    # lookup misses hold the raw address someone typed: they're for people who can add
    # members, not every viewer.
    def visible_activities
      scope = PublicActivity::Activity.where(trackable: @collection)
      return scope if policy(@collection).manage_members?

      scope.where.not(key: EMAIL_LOOKUP_MISS_KEY)
    end

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
