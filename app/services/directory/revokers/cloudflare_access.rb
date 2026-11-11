# frozen_string_literal: true

module Directory
  module Revokers
    # revoke_user is account-wide: it ends the person's sessions in every Access app on the
    # account, not just this one. Cloudflare has no per-user, per-app revoke.
    class CloudflareAccess < Base
      def call(email:)
        response = Outbound.post(
          "https://api.cloudflare.com/client/v4/accounts/#{@config['account_id']}/access/organizations/revoke_user",
          headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@config['api_token']}" },
          body: { email: email }.to_json
        )
        raise Directory::RevokeSessionJob::RevocationFailed, "cloudflare access revocation failed: #{response.status} #{response.excerpt}" unless response.success?

        :ok
      end
    end
  end
end
