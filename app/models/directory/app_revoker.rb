module Directory
  class AppRevoker < ApplicationRecord
    self.table_name = "directory_app_revokers"
    self.primary_key = :app_id

    ADAPTERS = %w[cloudflare_access webhook].freeze

    belongs_to :app, class_name: "Program"

    has_encrypted :config

    validates :adapter, presence: true, inclusion: { in: ADAPTERS }
    validates :config_ciphertext, presence: true
  end
end
