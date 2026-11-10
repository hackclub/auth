# frozen_string_literal: true

module Directory
  module Revokers
    class Webhook < Base
      def call(email:)
        if Directory::AppRevoker.internal_host?(URI.parse(@config["url"]).host)
          raise ArgumentError, "webhook url resolves to a private or local address"
        end

        response = HTTP.timeout(connect: 5, write: 5, read: 10).post(
          @config["url"],
          json: { email: email },
          headers: webhook_headers
        )

        unless response.status.success?
          raise Directory::RevokeSessionJob::RevocationFailed, "webhook revocation failed: #{response.status} #{body_excerpt(response)}"
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
