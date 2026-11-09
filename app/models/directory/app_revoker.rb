# frozen_string_literal: true

module Directory
  class AppRevoker < ApplicationRecord
    self.primary_key = :app_id

    ADAPTERS = %w[cloudflare_access webhook].freeze

    # Per adapter: config keys, and whether each is secret (never rendered back) or required.
    FIELDS = {
      "cloudflare_access" => { "account_id" => { required: true }, "api_token" => { required: true, secret: true } },
      "webhook" => { "url" => { required: true }, "secret" => { secret: true } }
    }.freeze

    belongs_to :app, class_name: "Program"

    has_encrypted :config

    validates :adapter, presence: true, inclusion: { in: ADAPTERS }
    validates :config_ciphertext, presence: true
    validate :required_fields_present
    validate :webhook_url_is_https, if: -> { adapter == "webhook" }

    def settings = config.present? ? JSON.parse(config) : {}

    # Blank secret fields keep what's stored, so secrets never need rendering back to survive
    # an edit. Switching adapter starts from scratch.
    def assign_settings(adapter:, fields:)
      allowed = FIELDS.fetch(adapter, {})
      submitted = fields.to_h.slice(*allowed.keys).transform_values { |v| v.to_s.strip }
      kept = adapter == self.adapter ? settings : {}
      merged = kept.merge(submitted.reject { |key, value| value.blank? && allowed.dig(key, :secret) })

      self.adapter = adapter
      self.config = merged.compact_blank.to_json
    end

    def secret_set?(key) = settings[key].present?

    private

    def required_fields_present
      FIELDS.fetch(adapter.to_s, {}).each do |key, opts|
        errors.add(:base, "#{key.humanize(capitalize: false)} is required") if opts[:required] && settings[key].blank?
      end
    end

    def webhook_url_is_https
      url = settings["url"]
      return if url.blank?

      uri = URI.parse(url)
      errors.add(:base, "webhook url must be https") unless uri.is_a?(URI::HTTPS) && uri.host.present?
    rescue URI::InvalidURIError
      errors.add(:base, "webhook url isn't a valid url")
    end
  end
end
