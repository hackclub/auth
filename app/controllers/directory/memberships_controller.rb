# frozen_string_literal: true

module Directory
  class MembershipsController < BaseController
    # Adding by email answers "does this address have an hca account?", so SPEC §3.1 has
    # every lookup audited and each person rate limited. One budget covers both add
    # actions, and since a batch is one request its size is capped too. Admins are exempt:
    # the admin people page already searches every identity.
    ADD_RATE_LIMIT = 20
    ADD_RATE_WINDOW = 10.minutes
    MAX_BATCH_IDENTIFIERS = 100

    # rate_limit captures its store when the class loads, and the test env's :null_store
    # never counts, so the limit goes through a delegator specs can point at a real store.
    ADD_RATE_STORE = SimpleDelegator.new(Rails.cache)

    rate_limit to: ADD_RATE_LIMIT, within: ADD_RATE_WINDOW, store: ADD_RATE_STORE, name: "add-member",
      by: -> { current_identity.id }, with: -> { refuse_rate_limited },
      only: %i[create batch_create], unless: :directory_admin?

    def create
      @collection = Directory::Collection.find_by!(slug: params[:collection_slug])
      authorize @collection, policy_class: Directory::MembershipPolicy

      expires_at = validated_expires_at
      return if expires_at == :invalid

      membership = @collection.memberships.new(
        created_by_identity_id: current_identity.id,
        expires_at: expires_at
      )

      if params[:email].present?
        # Add by email or public ID — find identity, create directory person if needed
        identity = lookup_identity(params[:email].strip)
        unless identity
          redirect_back fallback_location: directory_collection_path(@collection.slug),
            alert: t("directory.flash.email_not_found")
          return
        end
        person = find_or_create_person!(identity)
        membership.member_person = person

      elsif params[:group_slug].present?
        group = Directory::Collection.groups.find_by!(slug: params[:group_slug].strip)
        refusal = group_membership_refusal(group)
        if refusal
          redirect_back fallback_location: directory_collection_path(@collection.slug), alert: refusal
          return
        end
        membership.member_group = group

      elsif params[:member_person_id].present?
        person = Directory::Person.find_by(id: params[:member_person_id])
        unless person
          redirect_back fallback_location: directory_collection_path(@collection.slug),
            alert: t("directory.flash.member_not_found")
          return
        end
        # Non-admins can only add people they have visibility to
        unless policy(person).show?
          redirect_back fallback_location: directory_collection_path(@collection.slug),
            alert: t("directory.flash.member_not_found")
          return
        end
        membership.member_person = person

      elsif params[:member_group_id].present?
        group = Directory::Collection.find_by(id: params[:member_group_id])
        unless group
          redirect_back fallback_location: directory_collection_path(@collection.slug),
            alert: t("directory.flash.member_not_found")
          return
        end
        unless policy(group).show?
          redirect_back fallback_location: directory_collection_path(@collection.slug),
            alert: t("directory.flash.member_not_found")
          return
        end
        refusal = group_membership_refusal(group)
        if refusal
          redirect_back fallback_location: directory_collection_path(@collection.slug), alert: refusal
          return
        end
        membership.member_group = group

      else
        redirect_back fallback_location: directory_collection_path(@collection.slug),
          alert: t("directory.flash.provide_email_or_slug")
        return
      end

      Directory.mutate!(cause: Directory.cause("membership_created", actor: current_identity.id)) do
        @collection.memberships.expired.where(member_person_id: membership.member_person_id).delete_all if membership.member_person_id
        membership.save!
      end

      redirect_back fallback_location: directory_collection_path(@collection.slug),
        notice: t("directory.flash.member_added")

    rescue ActiveRecord::RecordNotFound
      redirect_back fallback_location: directory_collection_path(@collection.slug),
        alert: t("directory.flash.member_not_found")
    rescue ActiveRecord::RecordInvalid => e
      redirect_back fallback_location: directory_collection_path(@collection.slug),
        alert: e.record.errors.full_messages.to_sentence
    rescue ActiveRecord::InvalidForeignKey
      redirect_back fallback_location: directory_collection_path(@collection.slug),
        alert: t("directory.flash.member_not_found")
    rescue ActiveRecord::RecordNotUnique
      redirect_back fallback_location: directory_collection_path(@collection.slug),
        alert: t("directory.flash.already_a_member")
    end

    def batch_create
      @collection = Directory::Collection.find_by!(slug: params[:collection_slug])
      # a batch is N single adds, so it needs exactly what create does. explicit because
      # pundit would otherwise ask the policy for batch_create?, which doesn't exist.
      authorize @collection, :create?, policy_class: Directory::MembershipPolicy

      expires_at = validated_expires_at
      return if expires_at == :invalid

      identifiers = Array(params[:identifiers]).grep(String).map(&:strip).reject(&:blank?).uniq
      if identifiers.empty?
        redirect_back fallback_location: directory_collection_path(@collection.slug),
          alert: t("directory.flash.provide_email_or_slug")
        return
      end
      if identifiers.size > MAX_BATCH_IDENTIFIERS
        redirect_back fallback_location: directory_collection_path(@collection.slug),
          alert: t("directory.flash.batch_too_many", max: MAX_BATCH_IDENTIFIERS)
        return
      end

      added = []
      skipped = []
      not_found = []

      identities_by_identifier = bulk_lookup_identities(identifiers)
      not_found = identifiers.reject { |id| identities_by_identifier.key?(id) }

      if identities_by_identifier.any?
        Directory.mutate!(cause: Directory.cause("batch_membership_created", actor: current_identity.id)) do
          identities_by_identifier.each do |identifier, identity|
            person = find_or_create_person!(identity)

            if Directory::Membership.active.exists?(collection: @collection, member_person: person)
              skipped << identifier
              next
            end

            @collection.memberships.expired.where(member_person: person).delete_all

            Directory::Membership.create!(
              collection: @collection,
              member_person: person,
              expires_at: expires_at,
              created_by_identity_id: current_identity.id
            )
            added << identifier
          rescue ActiveRecord::RecordNotUnique
            skipped << identifier
          rescue ActiveRecord::RecordInvalid
            not_found << identifier
          end
        end
      end

      parts = []
      parts << t("directory.flash.batch_added", count: added.size) if added.any?
      parts << t("directory.flash.batch_skipped", count: skipped.size) if skipped.any?
      parts << t("directory.flash.batch_not_found", count: not_found.size, items: not_found.first(3).join(", ")) if not_found.any?

      redirect_back fallback_location: directory_collection_path(@collection.slug),
        notice: parts.join(". ")
    end

    def destroy
      membership = Directory::Membership.find(params[:id])
      @collection = membership.collection
      authorize membership

      # Admin only for removing member groups from entitlements (§4)
      if membership.member_group_id.present? && @collection.entitlement? && !directory_admin?
        redirect_back fallback_location: directory_collection_path(@collection.slug),
          alert: t("directory.flash.admin_only_remove_group")
        return
      end

      # Bilateral check: removing a group from a group requires permission on both
      if membership.member_group_id.present? && @collection.group? && !directory_admin?
        child = Directory::Collection.find_by(id: membership.member_group_id)
        if child && !pundit_user.can?(:manage_members, child)
          redirect_back fallback_location: directory_collection_path(@collection.slug),
            alert: t("directory.flash.need_manage_on_child_group")
          return
        end
      end

      Directory.mutate!(cause: Directory.cause("membership_removed", target: membership.id, actor: current_identity.id)) do
        membership.destroy!
      end

      redirect_back fallback_location: directory_collection_path(@collection.slug),
        notice: t("directory.flash.member_removed")
    end

    private

    def find_or_create_person!(identity)
      Directory::Person.find_or_create_for_identity!(identity, created_by: current_identity)
    end

    def validated_expires_at
      raw = params[:expires_at].presence
      return nil unless raw
      parsed = Time.zone.parse(raw.to_s)
      unless parsed
        redirect_back fallback_location: directory_collection_path(@collection.slug),
          alert: t("directory.flash.invalid_expires_at")
        return :invalid
      end
      parsed
    rescue ArgumentError
      redirect_back fallback_location: directory_collection_path(@collection.slug),
        alert: t("directory.flash.invalid_expires_at")
      :invalid
    end

    def refuse_rate_limited
      Rails.logger.warn("[Directory] add-by-identifier: #{current_identity.primary_email} rate limited on #{params[:collection_slug]}")
      redirect_back fallback_location: directory_collection_path(params[:collection_slug]),
        alert: t("directory.flash.add_rate_limited")
    end

    def bulk_lookup_identities(identifiers)
      emails, public_ids = identifiers.partition { |id| !id.start_with?("ident!") }

      result = {}

      if emails.any?
        by_email = Identity.where("lower(primary_email) IN (?)", emails.map(&:downcase)).index_by { |i| i.primary_email.downcase }
        emails.each { |e| result[e] = by_email[e.downcase] if by_email[e.downcase] }
      end

      public_ids.each do |pid|
        identity = Identity.find_by_public_id(pid)
        next unless identity
        next unless directory_admin? || Directory::Person.exists?(identity_id: identity.id)
        result[pid] = identity
      end

      identifiers.each do |identifier|
        sanitized = identifier.gsub(/[\r\n]/, " ")
        Rails.logger.info("[Directory] add-by-identifier: #{current_identity.primary_email} searched for '#{sanitized}' on #{@collection.slug}")
        unless result.key?(identifier)
          Rails.logger.info("[Directory] add-by-identifier: miss for '#{sanitized}'")
          @collection.create_activity :email_lookup_miss, owner: current_identity, params: { email: identifier }
        end
      end

      result
    end

    def resolve_identifier(input)
      return Identity.find_by("lower(primary_email) = ?", input.downcase) unless input.start_with?("ident!")

      identity = Identity.find_by_public_id(input)
      return identity if identity.nil? || directory_admin?

      identity if Directory::Person.exists?(identity_id: identity.id)
    end

    def group_membership_refusal(group)
      if @collection.entitlement? && !directory_admin?
        return t("directory.flash.admin_only_group_on_entitlement")
      end
      if @collection.group? && !directory_admin?
        nesting_refusal(group)
      end
    end

    # Why a non-admin can't nest `child` under @collection, or nil if they can (authorize
    # already covered the parent). Nesting carries every recursive grant that reaches
    # @collection, the actor's own included, down into child and its unprotected
    # sub-groups, so the actor must already manage all of them. Otherwise a recursive grant
    # on one group plus a plain one on another adds up to manage_members on everything
    # nested inside the second.
    def nesting_refusal(child)
      ctx = pundit_user
      return t("directory.flash.need_manage_on_child_group") unless ctx.can?(:manage_members, child)

      unless child.recursive_grant_reach.all? { |c| ctx.can?(:manage_members, c) }
        t("directory.flash.need_manage_on_child_subgroups")
      end
    end
  end
end
