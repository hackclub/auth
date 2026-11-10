# frozen_string_literal: true

module Directory
  module Revokers
    class Base
      def initialize(app_revoker)
        @app_revoker = app_revoker
        @config = JSON.parse(app_revoker.config)
      end

      def call(email:)
        raise NotImplementedError
      end

      private

      # an error page can be megabytes; this ends up in last_result and on the health page
      def body_excerpt(response)
        response.body.readpartial(4096).to_s.truncate(500)
      rescue EOFError
        ""
      end
    end
  end
end
