# frozen_string_literal: true

module Directory
  module Revokers
    def self.for(app_revoker)
      case app_revoker.adapter
      when "cloudflare_access" then CloudflareAccess.new(app_revoker)
      when "webhook" then Webhook.new(app_revoker)
      else raise "unknown revoker adapter: #{app_revoker.adapter}"
      end
    end
  end
end
