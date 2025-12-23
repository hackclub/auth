# Fix for RailsPulse RequestCollector middleware to handle blank paths/methods
# This prevents ActiveRecord::RecordInvalid errors when requests have blank paths
# which can happen with certain malformed requests or edge cases in production

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
        Rails.logger.error "[RailsPulse] Failed to find or create route: #{e.message} (method: #{method}, path: #{path})"
        nil
      rescue => e
        # Catch any other unexpected errors
        Rails.logger.error "[RailsPulse] Unexpected error in find_or_create_route: #{e.message}"
        nil
      end
    end
  end
end
