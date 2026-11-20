# frozen_string_literal: true

# Private submodule loader. See internal/README.md for structure.

module Internal
  class << self
    def available? = root.join("app").exist? && root.join("app").glob("*.rb").any?

    def root = Rails.root.join("internal")
  end
end

internal_path = Internal.root
app_path = internal_path.join("app")

if app_path.exist? && app_path.glob("*.rb").any?
  initializers_path = internal_path.join("initializers")
  if initializers_path.exist?
    Dir.glob(initializers_path.join("**/*.rb")).sort.each do |file|
      require file
    end
  end

  Rails.autoloaders.main.push_dir(app_path, namespace: Internal)

  views_path = internal_path.join("app", "views")
  if views_path.exist?
    ActiveSupport.on_load(:action_controller) do
      prepend_view_path views_path
    end
  end

  routes_path = internal_path.join("config", "routes.rb")
  if routes_path.exist?
    Rails.application.routes_reloader.paths << routes_path.to_s
  end

  locales_path = internal_path.join("config", "locales")
  if locales_path.exist?
    I18n.load_path += Dir[locales_path.join("**/*.{rb,yml}")]
  end

  Rails.logger.info "[InternalLoader] Loaded internal modules from #{internal_path}" if defined?(Rails.logger) && Rails.logger
else
  module Internal
    class Decisioning
      def self.run(verification) = Stubs::Decisioning.run(verification)
    end

    class Eligibility
      def self.manual_flow?(user) = Stubs::Eligibility.manual_flow?(user)
    end
  end
end
