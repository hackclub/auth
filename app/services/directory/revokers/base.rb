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
    end
  end
end
