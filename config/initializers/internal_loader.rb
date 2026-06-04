# frozen_string_literal: true

# Private submodule loader. See internal/README.md for structure.

module Internal
  class << self
    def available? = root.exist? && root.directory? && root.join("app").exist?

    def root = Rails.root.join("internal")
  end
end

internal_path = Internal.root

if internal_path.exist? && internal_path.directory?
  initializers_path = internal_path.join("initializers")
  if initializers_path.exist?
    Dir.glob(initializers_path.join("**/*.rb")).sort.each do |file|
      require file
    end
  end

  app_path = internal_path.join("app")

  Rails.autoloaders.main.push_dir(app_path, namespace: Internal) if app_path.exist?

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
