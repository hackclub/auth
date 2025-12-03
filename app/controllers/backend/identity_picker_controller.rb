# frozen_string_literal: true

module Backend
  class IdentityPickerController < ApplicationController
    skip_after_action :verify_authorized

    def search
      query = params[:q].to_s.strip
      results = []

      return render json: results if query.blank?

      if query.downcase.start_with?("ident!")
        identity = Identity.find_by_public_id(query) rescue nil
        if identity && policy(identity).show?
          results << format_identity(identity)
        end
      elsif query.length >= 2
        policy_scope(Identity).search(query.sub("mailto:", "")).limit(15).each do |identity|
          results << format_identity(identity)
        end
      end

      render json: results
    end

    private

    def format_identity(identity)
      {
        id: identity.public_id,
        label: identity.full_name,
        sublabel: identity.primary_email
      }
    end
  end
end
