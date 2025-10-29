require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module IdentityVault
  class Application < Rails::Application
    config.autoload_paths << "#{root}/app/views/forms"
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    config.semantic_logger.application = "identity-vault"
    config.semantic_logger.environment = Rails.env
    config.log_level = :info

    unless Rails.env.development?
      config.rails_semantic_logger.add_file_appender = false
      config.semantic_logger.add_appender(io: $stdout, formatter: :json)
      config.semantic_logger.add_appender(appender: :honeybadger_insights)
    end

    config.to_prepare do
      Doorkeeper::ApplicationController.layout "application"
      Doorkeeper::ApplicationController.skip_before_action :authenticate_identity!
      Backend::NoAuthController.skip_after_action :verify_authorized
    end

    config.session_store :cookie_store,
                         key: "_identity_vault_session_v2",
                         expire_after: 90.days,
                         secure: Rails.env.production?,
                         httponly: true,
                         same_site: :lax

    config.middleware.use Rack::Attack

    config.audits1984.base_controller_class = "Backend::NoAuthController"
    config.audits1984.auditor_class = "Backend::User"
    config.audits1984.auditor_name_attribute = :username

    config.console1984.ask_for_username_if_empty = true

    # Aadhaar verification configuration
    config.sanctioned_countries = config_for(:sanctioned_countries)

    config.saml = config_for(:saml)

    config.slack_channels = config_for(:slack_channels)

    # Slack E+ stuff (SAML, SCIM, etc.)
    

    # Use ImageMagick for image processing instead of VIPS
    config.active_storage.variant_processor = :mini_magick
  end
end
