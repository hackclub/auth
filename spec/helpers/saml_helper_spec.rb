# frozen_string_literal: true

require "rails_helper"

# build_saml_response is the one place assertions are made, so it's where access is enforced:
# a path that forgets to check first still can't produce an assertion it shouldn't.
RSpec.describe SAMLHelper do
  let(:helper) { Class.new { include SAMLHelper }.new }
  let(:identity) { create(:identity) }

  def sp(**settings)
    SAMLService::Entities.build_service_providers([ {
      slug: "test-sp",
      entity_id: "https://sp.example.test/metadata",
      assertion_consumer_services: [ { location: "https://sp.example.test/acs", binding: "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST" } ],
      **settings
    } ]).values.first
  end

  describe "#build_saml_response" do
    it "builds an assertion for an identity the SP admits" do
      response = helper.build_saml_response(identity:, sp_config: sp)

      expect(response.assertions.first.subject.name_id.id).to eq(identity.to_saml_nameid.id)
    end

    it "refuses an identity outside the SP's required entitlements" do
      Directory::Collection.create!(kind: "entitlement", slug: "test-sp-users", name: "Test SP Users")

      expect {
        helper.build_saml_response(identity:, sp_config: sp(required_entitlements: [ "test-sp-users" ]))
      }.to raise_error(SAMLHelper::AccessDenied, "this app is for hack club staff")
    end

    it "refuses an identity outside the SP's allowed_emails" do
      expect {
        helper.build_saml_response(identity:, sp_config: sp(allowed_emails: [ "someone-else@hackclub.com" ]))
      }.to raise_error(SAMLHelper::AccessDenied, "You are not authorized to access this service")
    end

    it "refuses Slack to an identity barred from it" do
      identity.update!(disallow_slack: true)

      expect {
        helper.build_saml_response(identity:, sp_config: sp(slug: "slack"))
      }.to raise_error(SAMLHelper::AccessDenied, "Unable to log in right now")
    end
  end
end
