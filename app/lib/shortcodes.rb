# frozen_string_literal: true

module Shortcodes
  class Shortcode < Data.define(:code, :label, :controller, :action, :icon, :role, :path_override)
    include Rails.application.routes.url_helpers

    def path
      return path_override if path_override
      return "/" if controller.nil?

      url_for(controller: controller, action: action, only_path: true)
    end
  end

  class << self
    def all(user = nil)
      shortcuts = []

      # Home
      shortcuts << Shortcode.new(code: "HOME", label: "Home", controller: "backend/static_pages", action: "index", icon: "⌂", role: :general, path_override: nil)

      # Most used: identities
      shortcuts << Shortcode.new(code: "IDNT", label: "Identities", controller: "backend/identities", action: "index", icon: "⭢", role: :general, path_override: nil)

      # MDV primary tasks
      if user&.manual_document_verifier? || user&.super_admin?
        shortcuts << Shortcode.new(code: "PEND", label: "Pending verifications", controller: "backend/verifications", action: "pending", icon: "⭢", role: :mdv, path_override: nil)
        shortcuts << Shortcode.new(code: "VERF", label: "All verifications", controller: "backend/verifications", action: "index", icon: "⭢", role: :mdv, path_override: nil)
      end

      # Common
      shortcuts << Shortcode.new(code: "LOGS", label: "Audit logs", controller: "backend/audit_logs", action: "index", icon: "⭢", role: :general, path_override: nil)

      # Program manager
      if user&.program_manager? || user&.super_admin?
        shortcuts << Shortcode.new(code: "APPS", label: "OAuth2 apps", controller: "backend/programs", action: "index", icon: "⭢", role: :program_manager, path_override: nil)
      end

      # Super admin (less frequent)
      if user&.super_admin?
        shortcuts += [
          Shortcode.new(code: "USRS", label: "Backend users", controller: "backend/users", action: "index", icon: "⭢", role: :super_admin, path_override: nil),
          Shortcode.new(code: "JOBS", label: "Job queue", controller: "good_job/jobs", action: "index", icon: "⭢", role: :super_admin, path_override: "/backend/good_job"),
          Shortcode.new(code: "FLIP", label: "Feature flags", controller: "flipper/features", action: "index", icon: "⭢", role: :super_admin, path_override: "/backend/flipper"),
          Shortcode.new(code: "ORWL", label: "Console audit", controller: "audits1984/audits", action: "index", icon: "⭢", role: :super_admin, path_override: "/backend/console_audit"),
          Shortcode.new(code: "PLSE", label: "Rails Pulse", controller: "rails_pulse/dashboard", action: "index", icon: "⭢", role: :super_admin, path_override: "/backend/rails_pulse")
        ]
      end

      # Exit last
      shortcuts << Shortcode.new(code: "EXIT", label: "Exit backend", controller: nil, action: nil, icon: "⭠", role: :general, path_override: nil)

      shortcuts
    end

    def find_by_code(code)
      all.find { |s| s.code.upcase == code.to_s.upcase }
    end

    def find_by_route(controller, action, user = nil)
      all(user).find { |s| s.controller == controller && s.action == action }
    end

    def to_json_for(user)
      all(user).map do |s|
        { code: s.code, label: s.label, path: s.path, icon: s.icon }
      end.to_json
    end

    def public_id_prefixes
      @public_id_prefixes ||= begin
        Rails.application.eager_load! if Rails.env.development?

        ActiveRecord::Base.descendants
          .select { |klass| klass.included_modules.include?(PublicIdentifiable) }
          .each_with_object({}) do |klass, hash|
            prefix = klass.get_public_id_prefix rescue next
            path = case klass.name
            when "Identity" then "/backend/identities"
            when "Verification" then "/backend/verifications"
            when "Address" then "/backend/identities"
            else "/backend/#{klass.name.underscore.pluralize}"
            end
            hash[prefix] = { model: klass.name, path: path }
          end
      end
    end

    def search_scopes_for(user)
      scopes = [ { key: "identities", label: "Identities", icon: "⭢" } ]

      if user&.super_admin? || user&.program_manager?
        scopes << { key: "oauth_apps", label: "OAuth apps", icon: "⭢" }
      end

      scopes
    end

    def kbar_data_for(user)
      {
        shortcuts: all(user).map { |s| { code: s.code, label: s.label, path: s.path, icon: s.icon } },
        prefixes: public_id_prefixes,
        searchScopes: search_scopes_for(user)
      }.to_json
    end
  end
end
