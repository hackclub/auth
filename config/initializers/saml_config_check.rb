# frozen_string_literal: true

# a service_providers entry the loader can't read raises SAMLService::Entities::ConfigError.
# check it at boot so a bad config/saml.yml fails the deploy instead of every SAML login and
# the home page. only parses the config: no database, no signing keys.
Rails.application.config.after_initialize do
  next if Rails.env.test?

  SAMLService::Entities.build_service_providers(Rails.application.config.saml.dig(:service_providers))
end
