# frozen_string_literal: true

module Directory
  class MembershipsController < BaseController
    def create
      @collection = Directory::Collection.find_by!(slug: params[:collection_slug])
      authorize @collection, policy_class: Directory::MembershipPolicy

      membership = @collection.memberships.new(
        created_by_identity_id: current_identity.id,
        expires_at: membership_params[:expires_at].presence
      )

      if membership_params[:email].present?
        identity = Identity.find_by!(primary_email: membership_params[:email])
        person = Directory::Person.find_or_create_by!(identity: identity) do |p|
          p.created_by_identity_id = current_identity.id
        end
        membership.member_person = person
      elsif membership_params[:member_group_id].present?
        if @collection.entitlement? && !directory_admin?
          redirect_back fallback_location: directory_collection_path(@collection.slug),
            alert: t("directory.memberships.admin_only_group_on_entitlement")
          return
        end
        membership.member_group_id = membership_params[:member_group_id]
      else
        membership.member_person_id = membership_params[:member_person_id]
      end

      ActiveRecord::Base.transaction do
        membership.save!
        Directory::Rebuild.call(cause: "membership_created:#{membership.id}")
      end

      redirect_back fallback_location: directory_collection_path(@collection.slug),
        notice: t("directory.memberships.created")
    rescue ActiveRecord::RecordInvalid => e
      redirect_back fallback_location: directory_collection_path(@collection.slug),
        alert: e.record.errors.full_messages.to_sentence
    end

    def destroy
      membership = Directory::Membership.find(params[:id])
      @collection = membership.collection
      authorize membership

      ActiveRecord::Base.transaction do
        membership.destroy!
        Directory::Rebuild.call(cause: "membership_deleted:#{membership.id}")
      end

      redirect_back fallback_location: directory_collection_path(@collection.slug),
        notice: t("directory.memberships.destroyed")
    end

    private

    def membership_params
      params.require(:membership).permit(:member_person_id, :member_group_id, :email, :expires_at)
    end
  end
end
