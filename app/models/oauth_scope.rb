# frozen_string_literal: true

class OAuthScope
  attr_reader :name, :description, :consent_fields, :includes, :icon

  def initialize(name:, description:, consent_fields: [], includes: [], icon: nil)
    @name = name
    @description = description
    @consent_fields = consent_fields
    @includes = includes
    @icon = icon
  end

  FIELD_ICONS = {
    email: "email",
    name: "person",
    phone: "phone",
    birthdate: "event-check",
    address: "home",
    verification_status: "check",
    ysws_eligible: "check",
    slack_id: "slack",
    legal_name: "card-id"
  }.freeze

  ALL = [
    new(
      name: "openid",
      description: "Enable OpenID Connect authentication",
      icon: "private"
    ),
    new(
      name: "email",
      description: "See your email address",
      icon: "email",
      consent_fields: [
        { key: :email, value: ->(ident) { ident.primary_email } }
      ]
    ),
    new(
      name: "name",
      description: "See your name",
      icon: "person",
      consent_fields: [
        { key: :name, value: ->(ident) { "#{ident.first_name} #{ident.last_name}" } }
      ]
    ),
    new(
      name: "profile",
      description: "See your name and profile information",
      icon: "profile",
      consent_fields: [
        { key: :name, value: ->(ident) { "#{ident.first_name} #{ident.last_name}" } }
      ]
    ),
    new(
      name: "phone",
      description: "See your phone number",
      icon: "phone",
      consent_fields: [
        { key: :phone, value: ->(ident) { ident.phone_number } }
      ]
    ),
    new(
      name: "birthdate",
      description: "See your date of birth",
      icon: "event-check",
      consent_fields: [
        { key: :birthdate, value: ->(ident) { ident.birthday&.strftime("%B %d, %Y") } }
      ]
    ),
    new(
      name: "address",
      description: "View your mailing address(es)",
      icon: "home",
      consent_fields: [
        { key: :address, value: ->(ident) {
          addr = ident.primary_address
          addr ? [ addr.line_1, addr.city, addr.state, addr.country ].compact.join(", ") : nil
        } }
      ]
    ),
    new(
      name: "verification_status",
      description: "See your verification status and YSWS eligibility",
      icon: "check",
      consent_fields: [
        { key: :verification_status, value: ->(ident) { ident.verification_status } },
        { key: :ysws_eligible, value: ->(ident) { ident.ysws_eligible ? "Yes" : "No" } }
      ]
    ),
    new(
      name: "slack_id",
      description: "See your Slack ID",
      icon: "slack",
      consent_fields: [
        { key: :slack_id, value: ->(ident) { ident.slack_id } }
      ]
    ),
    new(
      name: "legal_name",
      description: "See your legal name",
      icon: "card-id",
      consent_fields: [
        { key: :legal_name, value: ->(ident) { [ ident.legal_first_name, ident.legal_last_name ].compact.join(" ").presence } }
      ]
    ),
    new(
      name: "basic_info",
      description: "See basic information about you (email, name, verification status)",
      icon: "docs",
      includes: %w[email name slack_id phone birthdate verification_status]
    ),
    new(
      name: "set_slack_id",
      description: "Associate Slack IDs with identities",
      icon: "slack"
    )
  ].freeze

  BY_NAME = ALL.index_by(&:name).freeze

  COMMUNITY_ALLOWED = %w[openid profile email name slack_id verification_status].freeze

  def self.find(name)
    BY_NAME[name.to_s]
  end

  def self.known?(name)
    BY_NAME.key?(name.to_s)
  end

  def self.consent_fields_for(scope_names, identity)
    seen_keys = Set.new
    fields = []

    expanded_scopes(scope_names).each do |scope|
      scope.consent_fields.each do |field|
        next if seen_keys.include?(field[:key])
        seen_keys << field[:key]
        fields << {
          key: field[:key],
          value: field[:value].call(identity),
          icon: FIELD_ICONS[field[:key]]
        }
      end
    end

    fields
  end

  def self.consent_data_by_scope(scope_names, identity)
    result = {}
    seen_field_keys = Set.new

    scope_names.each do |name|
      scope = find(name)
      next unless scope
      next if scope.name == "openid"

      fields = scope.consent_fields.map do |field|
        { key: field[:key], value: field[:value].call(identity) }
      end

      scope.includes.each do |included_name|
        included_scope = find(included_name)
        next unless included_scope
        included_scope.consent_fields.each do |field|
          fields << { key: field[:key], value: field[:value].call(identity) }
        end
      end

      unique_fields = fields.uniq { |f| f[:key] }
      new_fields = unique_fields.reject { |f| seen_field_keys.include?(f[:key]) }

      next if new_fields.empty? && unique_fields.any?

      new_fields.each { |f| seen_field_keys << f[:key] }

      result[name] = {
        description: scope.description,
        icon: scope.icon,
        fields: new_fields
      }
    end

    result
  end

  def self.expanded_scopes(scope_names)
    scope_names.flat_map do |name|
      scope = find(name)
      next [] unless scope
      [ scope ] + scope.includes.filter_map { |n| find(n) }
    end
  end
end
