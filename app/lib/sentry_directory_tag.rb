# frozen_string_literal: true

# tags every directory services error feature=directory, so they can be filtered and
# alerted on as one thing: directory controllers and jobs (by transaction), Directory::
# exceptions, and anything raised from directory code paths (by backtrace)
module SentryDirectoryTag
  TAG = "directory"
  BACKTRACE = %r{app/(?:\w+/)*directory/|app/services/deletion_service\.rb|app/services/saml_service/access\.rb|config/initializers/doorkeeper\.rb}

  module_function

  def apply(event, hint)
    event.tags = (event.tags || {}).merge(feature: TAG) if directory?(event, hint)
    event
  end

  def directory?(event, hint)
    return true if event.transaction.to_s.start_with?("Directory::", "/directory")

    exception = hint && hint[:exception]
    return false unless exception

    exception.class.name.to_s.start_with?("Directory::") ||
      Array(exception.backtrace).any? { |line| line.match?(BACKTRACE) }
  end
end
