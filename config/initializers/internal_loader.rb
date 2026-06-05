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
