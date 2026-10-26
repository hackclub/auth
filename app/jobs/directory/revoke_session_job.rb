# frozen_string_literal: true

module Directory
  class RevokeSessionJob < ApplicationJob
    queue_as :default
    retry_on StandardError, wait: :polynomially_longer, attempts: 5

    def perform(app_id:, email:)
      revoker = Directory::AppRevoker.find_by(app_id: app_id, enabled: true)
      return unless revoker

      Directory::Revokers.for(revoker).call(email: email)
      revoker.update(last_called_at: Time.current, last_result: "ok")
    rescue => e
      revoker&.update(last_called_at: Time.current, last_result: "failed: #{e.message}")
      raise
    end
  end
end
