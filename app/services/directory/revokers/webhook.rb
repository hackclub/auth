# frozen_string_literal: true

module Directory
  module Revokers
    class Webhook < Base
      def call(email:)
        response = HTTP.timeout(connect: 5, write: 5, read: 10).post(
          @config["url"],
          json: { email: email },
          headers: webhook_headers
        )

        unless response.status.success?
          raise Directory::RevokeSessionJob::RevocationFailed, "webhook revocation failed: #{response.status} #{response.body}"
        end

        :ok
      end

      private

      def webhook_headers
        headers = { "Content-Type" => "application/json" }
        headers["Authorization"] = "Bearer #{@config['secret']}" if @config["secret"].present?
        headers
      end
    end
  end
end
