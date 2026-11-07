# frozen_string_literal: true

module Directory
  module Revokers
    class CloudflareAccess < Base
      def call(email:)
        response = HTTP.timeout(connect: 5, write: 5, read: 10)
          .auth("Bearer #{@config['api_token']}")
          .post(
            "https://api.cloudflare.com/client/v4/accounts/#{@config['account_id']}/access/organizations/revoke_user",
            json: { email: email }
          )

        unless response.status.success?
          raise Directory::RevokeSessionJob::RevocationFailed, "cloudflare access revocation failed: #{response.status} #{response.body}"
        end

        :ok
      end
    end
  end
end
