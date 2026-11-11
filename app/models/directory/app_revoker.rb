# frozen_string_literal: true

require "resolv"

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

    # a webhook mustn't be pointed back into our own network. anything that isn't plain
    # public unicast is out, including the ranges that tunnel to private space (cgnat,
    # nat64, 6to4, teredo, ipv4-compatible/translated). same coverage as the ssrf_filter gem
    BLOCKED_RANGES = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12
      192.0.0.0/24 192.0.2.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24
      203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
      ::/96 ::ffff:0:0:0/96 64:ff9b::/96 64:ff9b:1::/48 100::/64 100:0:0:1::/64
      2001::/32 2001:2::/48 2001:10::/28 2001:20::/28 2001:db8::/32 2002::/16
      3fff::/20 5f00::/16 fc00::/7 fe80::/10 ff00::/8
    ].map { |cidr| IPAddr.new(cidr) }.freeze

    # both as given and as the v4 address a mapped/compatible v6 one stands for
    def self.internal_ip?(ip)
      [ ip, ip.native ].uniq.any? do |candidate|
        BLOCKED_RANGES.any? { |range| range.family == candidate.family && range.include?(candidate) }
      end
    end

    # each try at each nameserver waits this long, so an unresponsive one costs ~2s, not ~75s
    DNS_TIMEOUTS = [ 1, 1 ].freeze

    # revoker hosts are fully qualified: search domains would only multiply the timeouts
    def self.dns_config = Resolv::DNS::Config.default_config_hash.merge(search: [], ndots: 1)

    # every address host resolves to, from /etc/hosts or DNS; [] when it doesn't resolve
    def self.resolve(host)
      bare = host.to_s.delete_prefix("[").delete_suffix("]")
      [ IPAddr.new(bare) ]
    rescue IPAddr::InvalidAddressError
      dns = Resolv::DNS.new(dns_config)
      dns.timeouts = DNS_TIMEOUTS
      Resolv.new([ Resolv::Hosts.new, dns ]).getaddresses(bare).map { |ip| IPAddr.new(ip.sub(/%.*\z/, "")) }.uniq
    end

    # for the save-time check: an unresolvable host is caught at call time instead
    def self.internal_host?(host)
      resolve(host).any? { |ip| internal_ip?(ip) }
    rescue IPAddr::Error
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
