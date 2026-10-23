# frozen_string_literal: true

module Directory
  module Revokers
    class CloudflareAccess < Base
      def call(email:)
        response = HTTP.auth("Bearer #{@config['api_token']}")
          .post(
            "https://api.cloudflare.com/client/v4/accounts/#{@config['account_id']}/access/organizations/revoke_user",
            json: { email: email }
          )

        unless response.status.success?
          raise "cloudflare access revocation failed: #{response.status} #{response.body}"
        end

        :ok
      end
    end
  end
end
