module API
  module External
    class IdentitiesController < ApplicationController
      FORTUNES = [
        "You can't have everything. Where would you put it?",
        "An ounce of action is worth a ton of theory.",
        "It is much harder to find a job than to keep one.",
        "You will be awarded some great honor.",
        "Don't look back, the lemmings are gaining on you.",
        "Today is the tomorrow you worried about yesterday.",
        "It's all in the mind, ya know.",
        "You have an unusual equipment for success. Use it properly.",
        "Go not to the elves for counsel, for they will say both yes and no.",
        "You will be successful in life.",
        "Never eat more than you can lift.",
        "Help! I'm trapped inside an identity provider!",
        "Big journeys begin with a single step.",
        "A fresh start will put you on your way.",
        "Your road to glory will be rocky, but fulfilling.",
        "Patience is a virtue, and you have it in abundance.",
        "Your lucky number is #{8.times.map { rand 37 }.join ", "}",
        "A dubious friend may be an enemy in camouflage.",
      ].freeze

      before_action :set_cors_headers, only: %i[check options]

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
        body = {
          result:,
          note: "This is a publicly accessible endpoint provided intentionally for integration purposes. " \
                "Accessing it does not constitute a security vulnerability and is not eligible for a bounty."
        }
        body[:your_fortune_is] = FORTUNES.sample if rand(1000) < 1
        render json: body
      end

      def options = head :ok

      private

      def set_cors_headers
        response.set_header("Access-Control-Allow-Origin", "*")
        response.set_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        response.set_header(
          "Access-Control-Allow-Headers",
          "Content-Type, Authorization"
        )
      end
    end
  end
end
