# frozen_string_literal: true

module Directory
  module Revokers
    class Webhook < Base
      def call(email:)
        response = Outbound.post(@config["url"], headers: webhook_headers, body: { email: email }.to_json)
        raise Directory::RevokeSessionJob::RevocationFailed, "webhook revocation failed: #{response.status} #{response.excerpt}" unless response.success?

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
