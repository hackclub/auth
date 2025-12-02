# frozen_string_literal: true

module Shortcodes
  Shortcode = Data.define(:code, :label, :path, :icon, :role)

  class << self
    def all(user = nil)
      shortcuts = []

      # Most used: identities
      shortcuts << Shortcode.new(code: "IDNT", label: "Identities", path: "/backend/identities", icon: "⭢", role: :general)

      # MDV primary tasks
      if user&.manual_document_verifier? || user&.super_admin?
        shortcuts << Shortcode.new(code: "PEND", label: "Pending verifications", path: "/backend/verifications/pending", icon: "⭢", role: :mdv)
        shortcuts << Shortcode.new(code: "VERF", label: "All verifications", path: "/backend/verifications", icon: "⭢", role: :mdv)
      end

      # Common
      shortcuts << Shortcode.new(code: "LOGS", label: "Audit logs", path: "/backend/audit_logs", icon: "⭢", role: :general)

      # Program manager
      if user&.program_manager? || user&.super_admin?
        shortcuts << Shortcode.new(code: "PROG", label: "Programs", path: "/backend/programs", icon: "⭢", role: :program_manager)
        shortcuts << Shortcode.new(code: "APPS", label: "OAuth2 apps", path: "/oauth/applications", icon: "⭢", role: :program_manager)
      end

      # Super admin (less frequent)
      if user&.super_admin?
        shortcuts += [
          Shortcode.new(code: "USRS", label: "Backend users", path: "/backend/users", icon: "⭢", role: :super_admin),
          Shortcode.new(code: "JOBS", label: "Job queue", path: "/backend/good_job", icon: "⭢", role: :super_admin),
          Shortcode.new(code: "FLIP", label: "Feature flags", path: "/backend/flipper", icon: "⭢", role: :super_admin),
          Shortcode.new(code: "ORWL", label: "Console audit", path: "/backend/console_audit", icon: "⭢", role: :super_admin)
        ]
      end

      # Exit last
      shortcuts << Shortcode.new(code: "EXIT", label: "Exit backend", path: "/", icon: "⭠", role: :general)

      shortcuts
    end

    def find_by_code(code)
      all.find { |s| s.code.upcase == code.to_s.upcase }
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
      scopes = [{ key: "identities", label: "Identities", icon: "⭢" }]

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
