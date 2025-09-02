module API
  module External
    class IdentitiesController < ApplicationController
      def check
        ident = if (public_id = params[:idv_id]).present?
                  Identity.find_by_public_id(public_id)
        elsif (primary_email = params[:email]).present?
                  Identity.find_by(primary_email:)
        elsif (slack_id = params[:slack_id]).present?
                  Identity.find_by(slack_id:)
        else
                  raise ActionController::ParameterMissing, "provide one of: idv_id, email, slack_id"
        end

        result = if ident
                   case ident.verification_status
                   when "needs_submission", "pending"
                     ident.verification_status
                   when "verified"
                     ident.ysws_eligible? ? "verified_eligible" : "verified_but_over_18"
                   when "ineligible"
                     "rejected"
                   else
                     "unknown"
                   end
        else
                   "not_found"
        end
        render json: {
          result:
        }
      end
    end
  end
end
