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
      before { allow(Sentry).to receive(:capture_exception) }

      # a misconfigured SP is skipped, not loaded — and reported to sentry
      def expect_sp_skipped(**overrides)
        result = described_class.build_service_providers([ sp_entry(**overrides) ])
        expect(result).to be_empty
      end

      it "skips an SP with an unknown key, like a typo of a security key" do
        expect_sp_skipped(required_entitlement: [ "airtable-users" ])
      end

      it "skips an SP with empty required_entitlements instead of reading it as no requirement" do
        expect_sp_skipped(required_entitlements: [])
        expect_sp_skipped(required_entitlements: nil)
        expect_sp_skipped(required_entitlements: [ "airtable-users", nil ])
      end

      it "skips an SP with empty allowed_emails instead of reading it as open to everyone" do
        expect_sp_skipped(allowed_emails: [])
      end

      it "skips an SP with entitlements that aren't a slug => value mapping" do
        expect_sp_skipped(entitlements: [ "airtable-users" ])
        expect_sp_skipped(entitlements: { "airtable-users": [ "a", "b" ] })
      end

      it "skips an SP with a groups_attribute that isn't a name" do
        expect_sp_skipped(groups_attribute: [ "groups" ])
      end

      it "skips an SP with entitlements it never requests, since the SAML2 gem would drop them" do
        expect_sp_skipped(
          entitlements: { "airtable-users": "airtable" },
          attribute_consuming_services: [ { name: "Profile", requested_attributes: [ { name: "email" } ] } ]
        )
        expect_sp_skipped(entitlements: { "airtable-users": "airtable" }, attribute_consuming_services: nil)
      end

      it "skips an SP with entitlements whose attribute allowed_attributes filters out" do
        expect_sp_skipped(entitlements: { "airtable-users": "airtable" }, allowed_attributes: [ "email" ])
      end

      it "skips an SP with no slug or entity_id" do
        expect_sp_skipped(slug: nil)
        expect_sp_skipped(entity_id: nil)
      end

      it "skips duplicate SPs instead of letting one silently shadow another" do
        result = described_class.build_service_providers([ sp_entry, sp_entry(slug: "airtable-2") ])
        expect(result.size).to eq(1)
        expect(Sentry).to have_received(:capture_exception)
          .with(an_instance_of(described_class::ConfigError).and(having_attributes(message: /entity_id/)))

        result = described_class.build_service_providers([ sp_entry, sp_entry(entity_id: "https://other.example/metadata") ])
        expect(result.size).to eq(1)
        expect(Sentry).to have_received(:capture_exception)
          .with(an_instance_of(described_class::ConfigError).and(having_attributes(message: /slug/)))
      end

      it "loads valid SPs even when another SP in the list is broken" do
        good = sp_entry
        bad = sp_entry(slug: "broken", entity_id: "https://broken.example/metadata", required_entitlements: [])
        result = described_class.build_service_providers([ good, bad ])

        expect(result.size).to eq(1)
        expect(result.values.first[:slug]).to eq("airtable")
        expect(Sentry).to have_received(:capture_exception).once
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

    it "sends the groups attribute empty when the person holds none, so SPs drop stale groups" do
      Directory::Collection.create!(kind: "entitlement", slug: "airtable-users", name: "Airtable Users")

      sp = load_sp(entitlements: { "airtable-users": "airtable" })
      response = helper.build_saml_response(identity:, sp_config: sp)

      attributes = response.assertions.first.statements.grep(SAML2::AttributeStatement).flat_map(&:attributes)
      groups = attributes.find { |attr| attr.name == "groups" }
      expect(groups).to be_present
      expect(Array(groups.value)).to be_empty
    end

    it "leaves the groups attribute out for an SP that doesn't map entitlements" do
      response = helper.build_saml_response(identity:, sp_config: load_sp)

      attributes = response.assertions.first.statements.grep(SAML2::AttributeStatement).flat_map(&:attributes)
      expect(attributes.map(&:name)).not_to include("groups")
    end
  end
end
