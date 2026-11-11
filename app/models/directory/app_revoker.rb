# frozen_string_literal: true

module Directory
  class AppRevoker < ApplicationRecord
    self.primary_key = :app_id

    ADAPTERS = %w[cloudflare_access webhook].freeze

    # Per adapter: config keys, and whether each is secret (never rendered back) or required.
    FIELDS = {
      "cloudflare_access" => { "account_id" => { required: true }, "api_token" => { required: true, secret: true, bound_to: "account_id" } },
      "webhook" => { "url" => { required: true }, "secret" => { secret: true, bound_to: "url" } }
    }.freeze

    belongs_to :app, class_name: "Program"

    has_encrypted :config
    # skip the plaintext virtual attribute too, or paper_trail records it in object_changes
    has_paper_trail skip: [ :config, :config_ciphertext ]

    validates :adapter, presence: true, inclusion: { in: ADAPTERS }
    validates :config_ciphertext, presence: true
    validate :required_fields_present
    validate :webhook_url_is_https, if: -> { adapter == "webhook" }
    validate :cloudflare_account_id_format, if: -> { adapter == "cloudflare_access" }
    validate :rebound_secrets_reentered

    UNREADABLE = [ Lockbox::Error, JSON::ParserError ].freeze

    def settings = config.present? ? JSON.parse(config) : {}

    # a row encrypted with another key, or hand-edited into bad json
    def readable?
      settings
      true
    rescue *UNREADABLE
      false
    end

    # Blank secret fields keep what's stored, so secrets never need rendering back to survive
    # an edit. Switching adapter starts from scratch, and so does a secret whose destination
    # changed: a kept webhook secret would otherwise be sent to the new url.
    def assign_settings(adapter:, fields:)
      allowed = FIELDS.fetch(adapter, {})
      submitted = fields.to_h.slice(*allowed.keys).transform_values { |v| v.to_s.strip }
      kept = adapter == self.adapter && readable? ? settings : {}
      @rebound_secrets = allowed.filter_map do |key, opts|
        bound = opts[:bound_to]
        key if bound && kept[key].present? && submitted[key].blank? &&
          submitted[bound].present? && submitted[bound] != kept[bound]
      end
      kept = kept.except(*@rebound_secrets)
      merged = kept.merge(submitted.reject { |key, value| value.blank? && allowed.dig(key, :secret) })

      self.adapter = adapter
      self.config = merged.compact_blank.to_json
    end

    def secret_set?(key) = readable? && settings[key].present?

    # the non-secret fields, for audit params: secrets only ever show as replaced
    def public_settings
      return {} unless readable?

      settings.reject { |key, _| FIELDS.dig(adapter.to_s, key, :secret) }
    end

    # a webhook mustn't be pointed back into our own network: checked on save and again
    # before every call, since DNS can change in between
    def self.internal_host?(host)
      addresses =
        begin
          [ IPAddr.new(host.to_s.delete_prefix("[").delete_suffix("]")) ]
        rescue IPAddr::InvalidAddressError
          Addrinfo.getaddrinfo(host, nil).map { |info| IPAddr.new(info.ip_address.sub(/%.*\z/, "")) }
        end
      addresses.any? do |ip|
        ip = ip.native
        ip.loopback? || ip.private? || ip.link_local? || ip.to_i.zero?
      end
    rescue SocketError, IPAddr::Error
      false
    end

    # Revocations with the same scope and email are the same call. Cloudflare's revoke_user
    # is account-wide, so every app on one account shares a scope.
    def session_scope_key
      adapter == "cloudflare_access" ? "cloudflare_access:#{settings['account_id']}" : "app:#{app_id}"
    end

    private

    def required_fields_present
      FIELDS.fetch(adapter.to_s, {}).each do |key, opts|
        next if (@rebound_secrets || []).include?(key)

        errors.add(:base, "#{key.humanize(capitalize: false)} is required") if opts[:required] && settings[key].blank?
      end
    end

    def rebound_secrets_reentered
      (@rebound_secrets || []).each do |key|
        bound = FIELDS.dig(adapter.to_s, key, :bound_to)
        errors.add(:base, "re-enter the #{key.humanize(capitalize: false)} when changing the #{bound.humanize(capitalize: false)}")
      end
    end

    def cloudflare_account_id_format
      account_id = settings["account_id"]
      return if account_id.blank? || account_id.match?(/\A\h{32}\z/)

      errors.add(:base, "cloudflare account id must be the 32-character hex id from the dashboard")
    end

    def webhook_url_is_https
      url = settings["url"]
      return if url.blank?

      uri = URI.parse(url)
      errors.add(:base, "webhook url must be https") unless uri.is_a?(URI::HTTPS) && uri.host.present?
      errors.add(:base, "webhook url can't point at a private or local address") if uri.host.present? && self.class.internal_host?(uri.host)
    rescue URI::InvalidURIError
      errors.add(:base, "webhook url isn't a valid url")
    end
  end
end
