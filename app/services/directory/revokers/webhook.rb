# frozen_string_literal: true

module Directory
  module Revokers
    class Webhook < Base
      def call(email:)
        response = HTTP.post(
          @config["url"],
          json: { email: email },
          headers: webhook_headers
        )

        unless response.status.success?
          raise "webhook revocation failed: #{response.status} #{response.body}"
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
