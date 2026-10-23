# frozen_string_literal: true

module Directory
  module Revokers
    def self.for(app_revoker)
      case app_revoker.adapter
      when "cloudflare_access" then CloudflareAccess.new(app_revoker)
      else raise "unknown revoker adapter: #{app_revoker.adapter}"
      end
    end

    class Base
      def initialize(app_revoker)
        @app_revoker = app_revoker
        @config = JSON.parse(app_revoker.config)
      end

      def call(email:)
        raise NotImplementedError
      end
    end
  end
end
