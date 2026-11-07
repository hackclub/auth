# frozen_string_literal: true

require "rails_helper"

RSpec.describe SAMLService::Entities do
  # one service_providers entry, shaped the way config_for(:saml) hands it over (symbol keys, all the way down)
  def sp_entry(**overrides)
    {
      slug: "airtable",
      friendly_name: "Airtable",
      entity_id: "https://airtable.example/metadata",
      allow_idp_initiated: true,
      assertion_consumer_services: [
        { location: "https://airtable.example/acs", binding: "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST" }
      ],
      attribute_consuming_services: [
        { name: "Airtable User Profile", requested_attributes: [ { name: "email", is_required: true }, { name: "groups" } ] }
      ]
    }.merge(overrides)
  end

  def load_sp(**overrides)
    described_class.build_service_providers([ sp_entry(**overrides) ]).values.first
  end

  describe ".build_service_providers" do
    it "keeps required_entitlements, entitlements and groups_attribute, in the shapes SAMLHelper reads" do
      sp = load_sp(
        required_entitlements: [ "airtable-users" ],
        entitlements: { "airtable-users": "airtable", "fulltimers-apps": "staff" },
        groups_attribute: "memberOf",
        attribute_consuming_services: [ { name: "Profile", requested_attributes: [ { name: "memberOf" } ] } ]
      )

      expect(sp[:required_entitlements]).to eq([ "airtable-users" ])
      expect(sp[:entitlements]).to eq("airtable-users" => "airtable", "fulltimers-apps" => "staff")
      expect(sp[:groups_attribute]).to eq("memberOf")
    end

    it "reads a single required entitlement as a list of one" do
      expect(load_sp(required_entitlements: "airtable-users")[:required_entitlements]).to eq([ "airtable-users" ])
    end

    it "reads a single allowed email as a list of one, so it's matched exactly and not as a substring" do
      expect(load_sp(allowed_emails: "nora@hackclub.com")[:allowed_emails]).to eq([ "nora@hackclub.com" ])
    end

    it "defaults to no requirement, no exposures, and the groups attribute" do
      sp = load_sp

      expect(sp[:required_entitlements]).to eq([])
      expect(sp[:entitlements]).to eq({})
      expect(sp[:groups_attribute]).to eq("groups")
    end

    describe "config it would otherwise drop or misread" do
      def expect_config_error(message, **overrides)
        expect { load_sp(**overrides) }.to raise_error(described_class::ConfigError, message)
      end

      it "rejects an unknown key, like a typo of a security key" do
        expect_config_error(/airtable.*unknown key.*required_entitlement\b/, required_entitlement: [ "airtable-users" ])
      end

      it "rejects an empty required_entitlements instead of reading it as no requirement" do
        expect_config_error(/required_entitlements/, required_entitlements: [])
        expect_config_error(/required_entitlements/, required_entitlements: nil)
        expect_config_error(/required_entitlements/, required_entitlements: [ "airtable-users", nil ])
      end

      it "rejects an empty allowed_emails instead of reading it as open to everyone" do
        expect_config_error(/allowed_emails/, allowed_emails: [])
      end

      it "rejects entitlements that aren't a slug => value mapping" do
        expect_config_error(/entitlements/, entitlements: [ "airtable-users" ])
        expect_config_error(/entitlements/, entitlements: { "airtable-users": [ "a", "b" ] })
      end

      it "rejects a groups_attribute that isn't a name" do
        expect_config_error(/groups_attribute/, groups_attribute: [ "groups" ])
      end

      it "rejects entitlements the SP never requests, since the SAML2 gem would drop them from the assertion" do
        expect_config_error(
          /requested_attributes/,
          entitlements: { "airtable-users": "airtable" },
          attribute_consuming_services: [ { name: "Profile", requested_attributes: [ { name: "email" } ] } ]
        )
        expect_config_error(/attribute_consuming_services/, entitlements: { "airtable-users": "airtable" }, attribute_consuming_services: nil)
      end

      it "rejects entitlements whose attribute allowed_attributes filters out" do
        expect_config_error(/allowed_attributes/, entitlements: { "airtable-users": "airtable" }, allowed_attributes: [ "email" ])
      end

      it "rejects an SP with no slug or entity_id" do
        expect_config_error(/slug/, slug: nil)
        expect_config_error(/entity_id/, entity_id: nil)
      end

      it "rejects two SPs with the same entity_id or slug, which would silently shadow one another" do
        expect {
          described_class.build_service_providers([ sp_entry, sp_entry(slug: "airtable-2") ])
        }.to raise_error(described_class::ConfigError, /entity_id/)

        expect {
          described_class.build_service_providers([ sp_entry, sp_entry(entity_id: "https://other.example/metadata") ])
        }.to raise_error(described_class::ConfigError, /slug/)
      end
    end
  end

  describe "config/saml.yml" do
    environments = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/saml.yml")).keys - [ "shared" ]

    it "has a section for every environment we deploy" do
      expect(environments).to include("development", "staging", "uat", "production")
    end

    environments.each do |env|
      it "loads every #{env} service provider" do
        sp_configs = Rails.application.config_for(:saml, env:)[:service_providers]

        expect(described_class.build_service_providers(sp_configs).size).to eq(Array(sp_configs).size)
      end
    end
  end

  describe "an SP loaded with entitlements" do
    let(:identity) { create(:identity) }
    let(:helper) { Class.new { include SAMLHelper }.new }

    it "puts the values for the entitlements the person holds, and only those, in the assertion's groups attribute" do
      entitled = Directory::Collection.create!(kind: "entitlement", slug: "airtable-users", name: "Airtable Users")
      Directory::Collection.create!(kind: "entitlement", slug: "fulltimers-apps", name: "Fulltimers Apps")
      person = Directory::Person.create!(identity:)
      Directory.mutate!(cause: "test") do
        Directory::Membership.create!(collection: entitled, member_person: person)
      end

      sp = load_sp(entitlements: { "airtable-users": "airtable", "fulltimers-apps": "staff" })
      response = helper.build_saml_response(identity:, sp_config: sp)

      attributes = response.assertions.first.statements.grep(SAML2::AttributeStatement).flat_map(&:attributes)
      expect(attributes.find { |attr| attr.name == "groups" }&.value).to eq([ "airtable" ])
    end
  end
end
