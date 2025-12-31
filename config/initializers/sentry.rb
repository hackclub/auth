git_hash = ENV["SOURCE_COMMIT"] || `git rev-parse HEAD` rescue "unknown"
short_hash = git_hash[0..7]
is_dirty = `git status --porcelain`.strip.length > 0 rescue false
git_version = is_dirty ? "#{short_hash}-dirty" : short_hash

Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.environment = Rails.env
  config.release = git_version
  config.enabled_environments = %w[production staging uat]
  config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]
  config.send_default_pii = true
  config.traces_sample_rate = Rails.env.production? ? 0.1 : 1.0
  config.enabled_patches = [ :http, :redis, :puma ]
  config.sdk_logger = Rails.logger

  # Capture error event IDs in Rack env for error pages
  config.rails.report_rescued_exceptions = true
end
