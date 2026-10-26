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
        # Add group by slug — admin only on entitlements (§3.2/§4)
        group = Directory::Collection.groups.find_by!(slug: params[:group_slug].strip)
        if @collection.entitlement? && !directory_admin?
          redirect_back fallback_location: directory_collection_path(@collection.slug),
            alert: t("directory.flash.admin_only_group_on_entitlement")
          return
        end
        membership.member_group = group

      elsif params[:member_person_id].present?
        membership.member_person_id = params[:member_person_id]

      elsif params[:member_group_id].present?
        # Enforce entitlement admin-only rule on ALL group-add paths (§3.2)
        if @collection.entitlement? && !directory_admin?
          redirect_back fallback_location: directory_collection_path(@collection.slug),
            alert: t("directory.flash.admin_only_group_on_entitlement")
          return
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

      ActiveRecord::Base.transaction do
        membership.destroy!
        Directory::Rebuild.call(cause: "membership_removed:#{membership.id}")
      end

      redirect_back fallback_location: directory_collection_path(@collection.slug),
        notice: t("directory.flash.member_removed")
    end
  end
end
