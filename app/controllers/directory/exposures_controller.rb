# frozen_string_literal: true

module Directory
  class ExposuresController < BaseController
    def create
      app = Program.find(params[:app_id])
      entitlement = Directory::Entitlement.find_by!(slug: params[:entitlement_slug])

      authorize_exposure!(app, entitlement)

      Directory::Exposure.create!(
        app: app,
        entitlement: entitlement,
        claim_name: params[:claim_name],
        created_by: current_identity
      )

      redirect_back fallback_location: developer_app_path(app), notice: "exposure added."
    rescue ActiveRecord::RecordInvalid => e
      redirect_back fallback_location: developer_app_path(app), alert: e.record.errors.full_messages.to_sentence
    end

    def destroy
      exposure = Directory::Exposure.find(params[:id])
      app = exposure.app

      authorize_unwire!(exposure)
      exposure.destroy!

      redirect_back fallback_location: developer_app_path(app), notice: "exposure removed."
    end

    private

    def authorize_exposure!(app, entitlement)
      unless app_owner?(app) && pundit_user.can?(:expose, entitlement) && app.hq_official?
        raise Pundit::NotAuthorizedError
      end
    end

    def authorize_unwire!(exposure)
      unless app_owner?(exposure.app) || pundit_user.can?(:expose, exposure.entitlement) || directory_admin?
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
