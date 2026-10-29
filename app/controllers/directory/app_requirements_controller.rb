# frozen_string_literal: true

module Directory
  class AppRequirementsController < ::ApplicationController
    include DirectoryAppAuthorization
    rescue_from Pundit::NotAuthorizedError do
      redirect_back fallback_location: root_path, alert: t("directory.flash.not_authorized")
    end
    before_action :authenticate_identity!

    def create
      app = Program.find(params[:app_id])
      entitlement = Directory::Collection.entitlements.find_by!(slug: params[:entitlement_slug])

      authorize_requirement!(app, entitlement)

      req = Directory::AppRequirement.create!(app: app, entitlement: entitlement)

      # §3.7: writing a requirement revokes tokens for non-members
      revoke_tokens_for_non_members(app, entitlement)

      redirect_back fallback_location: developer_app_path(app), notice: t("directory.flash.requirement_added")
    rescue ActiveRecord::RecordInvalid => e
      redirect_back fallback_location: developer_app_path(app), alert: e.record.errors.full_messages.to_sentence
    rescue ActiveRecord::RecordNotUnique
      redirect_back fallback_location: developer_app_path(app), alert: t("directory.flash.requirement_already_exists")
    end

    def destroy
      app = Program.find(params[:app_id])
      entitlement = Directory::Collection.find_by!(slug: params[:id])
      req = Directory::AppRequirement.find_by!(app_id: app.id, entitlement_id: entitlement.id)

      authorize_unwire!(app, entitlement)
      req.destroy!

      redirect_back fallback_location: developer_app_path(app), notice: t("directory.flash.requirement_removed")
    end

    private

    def authorize_requirement!(app, entitlement)
      ctx = directory_context
      unless app_owner?(app) && ctx.can?(:expose, entitlement) && app.hq_official?
        raise Pundit::NotAuthorizedError
      end
    end

    def authorize_unwire!(app, entitlement)
      ctx = directory_context
      return if ctx.admin?
      unless app_owner?(app) && ctx.can?(:expose, entitlement)
        raise Pundit::NotAuthorizedError
      end
    end


    # §3.7: revoke tokens for every token holder who isn't an effective member
    def revoke_tokens_for_non_members(app, _entitlement)
      # Requirements are any-of: revoke tokens for people who aren't a member
      # of ANY required entitlement (not just the one being added)
      all_required_ids = Directory::AppRequirement.where(app_id: app.id).pluck(:entitlement_id)

      # Find identity_ids of people who pass the requirement (member of any)
      passing_identity_ids = Directory::EffectiveMembership
        .where(collection_id: all_required_ids)
        .joins("INNER JOIN directory_people ON directory_people.id = directory_effective_memberships.person_id")
        .pluck("directory_people.identity_id")
        .uniq

      non_passing = ->(scope) { scope.where(application_id: app.id).where.not(resource_owner_id: passing_identity_ids).where(revoked_at: nil) }

      tokens_to_revoke = non_passing.call(OAuthToken)
      revoked_identity_ids = tokens_to_revoke.pluck(:resource_owner_id).uniq
      tokens_to_revoke.update_all(revoked_at: Time.current)
      non_passing.call(Doorkeeper::AccessGrant).update_all(revoked_at: Time.current)

      revoker = Directory::AppRevoker.find_by(app_id: app.id, enabled: true)
      if revoker && revoked_identity_ids.any?
        Identity.where(id: revoked_identity_ids).pluck(:primary_email).each do |email|
          Directory::RevokeSessionJob.perform_later(app_id: app.id, email: email)
        end
      end
    end
  end
end
