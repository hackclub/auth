# frozen_string_literal: true

module Directory
  class AppRequirementsController < BaseController
    def create
      app = Program.find(params[:app_id])
      entitlement = Directory::Entitlement.find_by!(slug: params[:entitlement_slug])

      authorize_requirement!(app, entitlement)

      Directory::AppRequirement.create!(
        app: app,
        entitlement: entitlement,
        created_by: current_identity
      )

      redirect_back fallback_location: developer_app_path(app), notice: "requirement added."
    rescue ActiveRecord::RecordInvalid => e
      redirect_back fallback_location: developer_app_path(app), alert: e.record.errors.full_messages.to_sentence
    end

    def destroy
      requirement = Directory::AppRequirement.find(params[:id])
      app = requirement.app

      authorize_unrequire!(requirement)
      requirement.destroy!

      redirect_back fallback_location: developer_app_path(app), notice: "requirement removed."
    end

    private

    def authorize_requirement!(app, entitlement)
      unless app_owner?(app) && pundit_user.can?(:expose, entitlement) && app.hq_official?
        raise Pundit::NotAuthorizedError
      end
    end

    def authorize_unrequire!(requirement)
      unless app_owner?(requirement.app) || pundit_user.can?(:expose, requirement.entitlement) || directory_admin?
        raise Pundit::NotAuthorizedError
      end
    end

    def app_owner?(app)
      app.owner_identity_id == current_identity.id ||
        ProgramCollaborator.accepted.exists?(program_id: app.id, identity_id: current_identity.id)
    end

    def skip_authorization? = true
  end
end
