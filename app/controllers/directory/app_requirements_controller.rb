# frozen_string_literal: true

module Directory
  class AppRequirementsController < ::ApplicationController
    before_action :authenticate_identity!

    def create
      app = Program.find(params[:app_id])
      entitlement = Directory::Entitlement.find_by!(slug: params[:entitlement_slug])

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
      entitlement = Directory::Collection.find(params[:id])
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
      unless app_owner?(app) || ctx.can?(:expose, entitlement) || ctx.admin?
        raise Pundit::NotAuthorizedError
      end
    end

    def app_owner?(app)
      app.owner_identity_id == current_identity.id ||
        ProgramCollaborator.where(program_id: app.id, identity_id: current_identity.id, status: "accepted").exists?
    end

    def directory_context
      person = Directory::Person.find_by(identity: current_identity)
      admin = current_identity.backend_user&.directory_services_admin?
      Directory::Context.new(identity: current_identity, person: person, admin: admin)
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

      # Revoke tokens for token holders who don't pass
      OAuthToken.where(application_id: app.id)
        .where.not(resource_owner_id: passing_identity_ids)
        .where(revoked_at: nil)
        .update_all(revoked_at: Time.current)

      revoker = Directory::AppRevoker.find_by(app_id: app.id, enabled: true)
      if revoker
        non_passing_emails = Identity
          .where(id: OAuthToken.where(application_id: app.id).select(:resource_owner_id))
          .where.not(id: passing_identity_ids)
          .pluck(:primary_email)

        non_passing_emails.each do |email|
          Directory::RevokeSessionJob.perform_later(app_id: app.id, email: email)
        end
      end
    end
  end
end
