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
        # Add-by-email: find identity, create directory person if needed
        Rails.logger.info("[Directory] add-by-email: #{current_identity.primary_email} searched for '#{params[:email]}' on #{@collection.slug}")
        identity = Identity.find_by("lower(primary_email) = ?", params[:email].strip.downcase)
        unless identity
          Rails.logger.info("[Directory] add-by-email: miss for '#{params[:email]}'")
          @collection.create_activity :email_lookup_miss, owner: current_identity, params: { email: params[:email] }
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

      ActiveRecord::Base.transaction do
        membership.save!
        Directory::Rebuild.call(cause: "membership:#{membership.id}")
      end

      redirect_back fallback_location: directory_collection_path(@collection.slug),
        notice: t("directory.flash.member_added")

    rescue ActiveRecord::RecordNotFound => e
      redirect_back fallback_location: directory_collection_path(@collection.slug),
        alert: e.message
    rescue ActiveRecord::RecordInvalid => e
      redirect_back fallback_location: directory_collection_path(@collection.slug),
        alert: e.record.errors.full_messages.to_sentence
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

      ActiveRecord::Base.transaction do
        membership.destroy!
        Directory::Rebuild.call(cause: "membership_removed:#{membership.id}")
      end

      redirect_back fallback_location: directory_collection_path(@collection.slug),
        notice: t("directory.flash.member_removed")
    end
  end
end
