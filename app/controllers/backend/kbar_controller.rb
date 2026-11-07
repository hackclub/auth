# frozen_string_literal: true

module Backend
  class KbarController < ApplicationController
    skip_after_action :verify_authorized

    def search
      query = params[:q].to_s.strip
      scope = params[:scope].to_s.strip
      results = []

      return render json: results if query.blank?

      # Check if it's a public ID pattern
      prefix = query.split("!").first.downcase
      prefix_info = Shortcodes.public_id_prefixes[prefix]

      if query.include?("!") && prefix_info
        begin
          # Safe to use constantize because prefix_info[:model] comes from
          # Shortcodes.public_id_prefixes which contains only whitelisted model names
          model_name = prefix_info[:model]
          klass = Object.const_get(model_name)
          record = if klass == Identity
            policy_scope(Identity).find_by_public_id(query)
          else
            klass.find_by_public_id(query)
          end
          if record
            results << build_result_for(record, prefix_info)
          end
        rescue
          nil
        end
      elsif scope.present?
        results = search_in_scope(scope, query)
      end

      render json: results
    end

    private

    def search_in_scope(scope, query)
      results = []

      case scope
      when "identities"
        policy_scope(Identity).search(query.sub("mailto:", "")).limit(10).each do |identity|
          results << {
            type: "identity",
            id: identity.public_id,
            label: identity.full_name,
            sublabel: identity.primary_email,
            path: "/backend/identities/#{identity.public_id}"
          }
        end

      when "oauth_apps"
        if current_user.super_admin? || current_user.program_manager?
          Program.where("name ILIKE ? OR uid = ?", "%#{query}%", query).limit(10).each do |app|
            results << {
              type: "oauth_app",
              id: app.id,
              label: app.name,
              sublabel: app.redirect_uri&.truncate(50),
              path: "/developer/apps/#{app.id}"
            }
          end
        end

      when "directory"
        if current_user.directory_services_admin?
          like = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
          Directory::Person.joins(:identity)
            .where("identities.first_name ILIKE :q OR identities.last_name ILIKE :q OR identities.primary_email ILIKE :q", q: like)
            .includes(:identity).limit(10).each do |person|
              results << { type: "directory_person", id: person.public_id, label: person.full_name, sublabel: person.primary_email, path: "/directory/people/#{person.public_id}" }
            end
          Directory::Collection.where("name ILIKE :q OR slug ILIKE :q", q: like).limit(10).each do |col|
            results << { type: "directory_collection", id: col.id, label: col.name, sublabel: "#{col.kind} · #{col.slug}", path: "/directory/collections/#{col.slug}" }
          end
        end
      end

      results
    end

    def build_result_for(record, prefix_info)
      type = prefix_info[:model].underscore
      base_path = prefix_info[:path]

      label, sublabel, path = case record
      when Identity
        [ record.full_name, record.primary_email, "#{base_path}/#{record.public_id}" ]
      when Address
        [ record.full_address, record.identity&.full_name, "/backend/identities/#{record.identity&.public_id}" ]
      when Verification
        [ "Verification #{record.public_id}", record.identity&.full_name, "#{base_path}/#{record.public_id}" ]
      else
        display = record.try(:name) || record.try(:title) || record.public_id
        [ display, nil, "#{base_path}/#{record.public_id}" ]
      end

      { type: type, id: record.public_id, label: label, sublabel: sublabel, path: path }
    end
  end
end
