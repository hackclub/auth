# frozen_string_literal: true

module SAMLService
  # Who may get an assertion for an SP. Checked on every assertion and when listing SSO tiles.
  # Losing a required entitlement doesn't end a session the SP already has: SAML leaves us
  # no token to revoke, so it only stops the next login.
  module Access
    module_function

    # Why identity may not log in to sp_config, or nil if it may.
    def denial(identity, sp_config, report_misconfiguration: true)
      if sp_config[:allowed_emails].present? && !sp_config[:allowed_emails].include?(identity.primary_email)
        return I18n.t("saml.denial.not_allowed")
      end

      if (reason = entitlement_denial(identity, sp_config, report_misconfiguration:))
        return reason
      end

      I18n.t("saml.denial.disallow_slack") if sp_config[:slug] == "slack" && identity.disallow_slack
    end

    # Any one required entitlement admits. A slug that doesn't resolve shuts everyone out
    # rather than quietly shrinking the list.
    def entitlement_denial(identity, sp_config, report_misconfiguration:)
      required = sp_config[:required_entitlements]
      return if required.blank?

      entitlements = Directory::Collection.entitlements.where(slug: required)
      missing_slugs = required - entitlements.pluck(:slug)

      if missing_slugs.any?
        if report_misconfiguration
          Rails.logger.error("[SAML] required_entitlements references missing slugs: #{missing_slugs.join(', ')} for SP #{sp_config[:slug]}")
          Sentry.capture_message("SAML requirement references missing entitlement", level: :error, extra: { sp: sp_config[:slug], missing_slugs: missing_slugs })
        end
        return I18n.t("saml.denial.misconfigured")
      end

      person = Directory::Person.find_by(identity: identity)
      unless person && Directory::EffectiveMembership.where(collection_id: entitlements.select(:id), person_id: person.id).exists?
        I18n.t("saml.denial.no_access")
      end
    end

    # SPs that would break (required_entitlements) or silently lose a group (entitlements)
    # if this entitlement slug went away.
    def service_providers_using_entitlement(slug)
      Entities.service_providers.values.select do |sp|
        sp[:required_entitlements].include?(slug) || sp[:entitlements].key?(slug)
      end
    end
  end
end
