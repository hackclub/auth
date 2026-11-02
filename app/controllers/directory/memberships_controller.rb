# frozen_string_literal: true

module Directory
  class MembershipsController < BaseController
    def create
      @collection = Directory::Collection.find_by!(slug: params[:collection_slug])
      authorize @collection, policy_class: Directory::MembershipPolicy

      membership = @collection.memberships.new(
        created_by_identity_id: current_identity.id,
        expires_at: params[:expires_at].presence
      )

      if params[:email].present?
        # Add by email or public ID — find identity, create directory person if needed
        input = params[:email].strip
        Rails.logger.info("[Directory] add-by-identifier: #{current_identity.primary_email} searched for '#{input}' on #{@collection.slug}")
        identity = resolve_identifier(input)
        unless identity
          Rails.logger.info("[Directory] add-by-identifier: miss for '#{input}'")
          @collection.create_activity :email_lookup_miss, owner: current_identity, params: { email: input }
          redirect_back fallback_location: directory_collection_path(@collection.slug),
            alert: t("directory.flash.email_not_found")
          return
        end
        person = Directory::Person.find_or_create_by!(identity: identity) do |p|
          p.created_by_identity_id = current_identity.id
        end
        membership.member_person = person

      elsif params[:group_slug].present?
        group = Directory::Collection.groups.find_by!(slug: params[:group_slug].strip)
        if @collection.entitlement? && !directory_admin?
          redirect_back fallback_location: directory_collection_path(@collection.slug),
            alert: t("directory.flash.admin_only_group_on_entitlement")
          return
        end
        # §3.5 escalation prevention: nesting group X under group G with a recursive
        # grant on G gives manage_members on X. require permission on BOTH sides.
        if @collection.group? && !directory_admin?
          ctx = pundit_user
          unless ctx.can?(:manage_members, group)
            redirect_back fallback_location: directory_collection_path(@collection.slug),
              alert: t("directory.flash.need_manage_on_child_group")
            return
          end
        end
        membership.member_group = group

      elsif params[:member_person_id].present?
        membership.member_person_id = params[:member_person_id]

      elsif params[:member_group_id].present?
        if @collection.entitlement? && !directory_admin?
          redirect_back fallback_location: directory_collection_path(@collection.slug),
            alert: t("directory.flash.admin_only_group_on_entitlement")
          return
        end
        # Same bilateral check for raw member_group_id path
        if @collection.group? && !directory_admin?
          child = Directory::Collection.find(params[:member_group_id])
          ctx = pundit_user
          unless ctx.can?(:manage_members, child)
            redirect_back fallback_location: directory_collection_path(@collection.slug),
              alert: t("directory.flash.need_manage_on_child_group")
            return
          end
        end
        membership.member_group_id = params[:member_group_id]

      else
        redirect_back fallback_location: directory_collection_path(@collection.slug),
          alert: t("directory.flash.provide_email_or_slug")
        return
      end

      Directory.mutate!(cause: Directory.cause("membership_created", actor: current_identity.id)) do
        membership.save!
      end

      redirect_back fallback_location: directory_collection_path(@collection.slug),
        notice: t("directory.flash.member_added")

    rescue ActiveRecord::RecordNotFound => e
      redirect_back fallback_location: directory_collection_path(@collection.slug),
        alert: e.message
    rescue ActiveRecord::RecordInvalid => e
      redirect_back fallback_location: directory_collection_path(@collection.slug),
        alert: e.record.errors.full_messages.to_sentence
    rescue ActiveRecord::InvalidForeignKey
      redirect_back fallback_location: directory_collection_path(@collection.slug),
        alert: t("directory.flash.member_not_found")
    end

    def batch_create
      @collection = Directory::Collection.find_by!(slug: params[:collection_slug])
      # a batch is N single adds, so it needs exactly what create does. explicit because
      # pundit would otherwise ask the policy for batch_create?, which doesn't exist.
      authorize @collection, :create?, policy_class: Directory::MembershipPolicy

      identifiers = Array(params[:identifiers]).map(&:strip).reject(&:blank?).uniq
      if identifiers.empty?
        redirect_back fallback_location: directory_collection_path(@collection.slug),
          alert: t("directory.flash.provide_email_or_slug")
        return
      end

      added = []
      skipped = []
      not_found = []
      resolved = []

      identifiers.each do |identifier|
        identity = resolve_identifier(identifier)

        unless identity
          not_found << identifier
          next
        end

        person = Directory::Person.find_or_create_by!(identity: identity) do |p|
          p.created_by_identity_id = current_identity.id
        end

        if Directory::Membership.exists?(collection: @collection, member_person: person)
          skipped << identifier
          next
        end

        resolved << { identifier: identifier, person: person }
      end

      if resolved.any?
        Directory.mutate!(cause: Directory.cause("batch_membership_created", actor: current_identity.id)) do
          resolved.each do |entry|
            next if Directory::Membership.exists?(collection: @collection, member_person: entry[:person])

            Directory::Membership.create!(
              collection: @collection,
              member_person: entry[:person],
              expires_at: params[:expires_at].presence,
              created_by_identity_id: current_identity.id
            )
            added << entry[:identifier]
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

    # Turns an add-by-identifier input into an identity, or nil for a miss. An exact email
    # may bring a new identity into the directory (SPEC §3.1). Public IDs are guessable
    # (unsalted hashids over sequential ids), so for non-admins an ident! only reaches
    # people already in the directory, the same reach the picker has; any other identity
    # is a miss, indistinguishable from one that doesn't exist.
    def resolve_identifier(input)
      return Identity.find_by("lower(primary_email) = ?", input.downcase) unless input.start_with?("ident!")

      identity = Identity.find_by_public_id(input)
      return identity if identity.nil? || directory_admin?

      identity if Directory::Person.exists?(identity_id: identity.id)
    end
  end
end
