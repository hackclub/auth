# Fix for RailsPulse RequestCollector middleware to handle blank paths/methods
#
# Issue: ActiveRecord::RecordInvalid: Validation failed: Route can't be blank
# This error occurs in production when RailsPulse tries to track requests with blank
# paths or methods, which can happen with:
#   - Malformed HTTP requests
#   - Certain edge cases in the middleware chain
#   - Unusual client behavior
#
# Root cause: The gem's find_or_create_route method doesn't validate path/method
# before calling find_or_create_by, which raises an exception when validations fail
# on the RailsPulse::Route model (which requires both method and path to be present).
#
# Solution: Monkey-patch the find_or_create_route method to:
#   1. Check if path or method is blank before attempting database operations
#   2. Return nil for invalid routes - the existing middleware code at line 46 in
#      request_collector.rb has "if route" which gracefully skips request creation
#   3. Rescue any remaining validation errors to prevent middleware crashes
#
# This ensures the middleware chain continues to work even when encountering
# problematic requests, while logging the issues for debugging.
#
# TODO: Consider contributing this fix upstream to the RailsPulse gem to benefit
# the broader community and avoid maintenance burden of monkey-patching.

Rails.application.config.after_initialize do
  if defined?(RailsPulse::Middleware::RequestCollector)
    RailsPulse::Middleware::RequestCollector.class_eval do
      private

      def find_or_create_route(req)
        method = req.request_method
        path = req.path

        # Return nil if path or method is blank to prevent validation errors
        return nil if path.blank? || method.blank?

        RailsPulse::Route.find_or_create_by(method: method, path: path)
      rescue ActiveRecord::RecordInvalid => e
        # Log the error but don't crash the middleware
        # Sanitize path to avoid logging sensitive data (e.g., tokens, params)
        sanitized_path = path.to_s.split('?').first.truncate(100)
        Rails.logger.error "[RailsPulse] Failed to find or create route: #{e.message} (method: #{method}, path: #{sanitized_path})"
        nil
      rescue => e
        # Catch any other unexpected errors
        Rails.logger.error "[RailsPulse] Unexpected error in find_or_create_route: #{e.message}"
        nil
      end
    end
  end
end
