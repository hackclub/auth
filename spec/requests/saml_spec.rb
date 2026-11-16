# frozen_string_literal: true

require "rails_helper"
require_relative "../support/saml_test_helpers"

RSpec.describe "SAML access checks", type: :request do
  include SAMLTestHelpers

  let(:entity_id) { "https://sp.example.test/metadata" }
  let(:acs_url) { "https://sp.example.test/acs" }
  let(:sp_settings) { {} }
  let(:identity) { create(:identity) }

  before do
    use_saml_service_providers({
      slug: "test-sp",
      friendly_name: "Test SP",
      entity_id: entity_id,
      allow_idp_initiated: true,
      allow_unsigned_requests: true,
      assertion_consumer_services: [ { location: acs_url, binding: SAMLTestHelpers::HTTP_POST_BINDING } ],
      attribute_consuming_services: [
        { name: "Test SP Profile", requested_attributes: [ { name: "email" }, { name: "groups" } ] }
      ]
    }.merge(sp_settings))
    stub_saml_signing
    Flipper.enable(:are_we_enterprise_yet_2025_10_21)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
  end

  after { Flipper.disable(:are_we_enterprise_yet_2025_10_21) }

  def idp_initiated
    post idp_initiated_saml_path(slug: "test-sp")
  end

  # an unsigned HTTP-Redirect AuthnRequest, as the SP would send it (the SP allows unsigned requests)
  def sp_initiated
    sp = SAMLService::Entities.sp_by_entity_id(entity_id)[:entity].service_providers.first
    authn_request = SAML2::AuthnRequest.initiate(SAML2::NameID.new(entity_id), service_provider: sp)
    authn_request.destination = "http://www.example.com#{SAMLController::SSO_ENDPOINT_PATH}"
    get SAML2::Bindings::HTTPRedirect.encode(authn_request)
    authn_request
  end

  def expect_assertion_posted
    expect(response).to have_http_status(:ok)
    expect(saml_post_target).to eq(acs_url)
    expect(posted_name_id).to eq(identity.to_saml_nameid.id)
  end

  def expect_refused(message)
    expect(response).to have_http_status(:forbidden)
    expect(response.body).to include(CGI.escapeHTML(message))
    expect(posted_saml_response).to be_nil
  end

  describe "an SP with required_entitlements" do
    let(:sp_settings) { { required_entitlements: [ "test-sp-users" ], entitlements: { "test-sp-users": "member" } } }
    let!(:required) { entitlement!("test-sp-users") }

    describe "IdP-initiated" do
      it "posts an assertion, groups and all, for an effective member" do
        add_member!(required, identity:)

        idp_initiated

        expect_assertion_posted
        groups = posted_saml_response.xpath("//saml:Attribute[@Name='groups']/saml:AttributeValue", "saml" => SAML2::Namespaces::SAML)
        expect(groups.map(&:text)).to eq([ "member" ])
      end

      it "admits someone who's a member through a nested group" do
        team = Directory::Collection.create!(kind: "group", slug: "test-sp-team", name: "Test SP Team")
        add_member!(team, identity:)
        add_member!(required, group: team)

        idp_initiated

        expect_assertion_posted
      end

      it "refuses a non-member with the error page and no assertion" do
        idp_initiated

        expect_refused(I18n.t("saml.denial.no_access"))
      end
    end

    describe "SP-initiated" do
      it "answers a member's AuthnRequest with an assertion" do
        add_member!(required, identity:)

        authn_request = sp_initiated

        expect_assertion_posted
        expect(posted_saml_response.root["InResponseTo"]).to eq(authn_request.id)
      end

      it "refuses a non-member with the error page and no assertion" do
        sp_initiated

        expect_refused(I18n.t("saml.denial.no_access"))
      end
    end

    describe "when a required entitlement doesn't exist" do
      let(:sp_settings) { { required_entitlements: [ "test-sp-users", "deleted-entitlement" ] } }

      before { add_member!(required, identity:) }

      it "fails closed for IdP-initiated logins, even for members of the slug that does exist" do
        idp_initiated

        expect_refused(I18n.t("saml.denial.misconfigured"))
      end

      it "fails closed for SP-initiated logins too" do
        sp_initiated

        expect_refused(I18n.t("saml.denial.misconfigured"))
      end
    end
  end

  describe "an SP with allowed_emails" do
    context "that lists the identity's email" do
      let(:sp_settings) { { allowed_emails: [ "someone-else@hackclub.com", identity.primary_email ] } }

      it "posts an assertion, IdP- or SP-initiated" do
        idp_initiated
        expect_assertion_posted

        sp_initiated
        expect_assertion_posted
      end
    end

    context "that doesn't" do
      let(:sp_settings) { { allowed_emails: [ "someone-else@hackclub.com" ] } }

      it "refuses, IdP- or SP-initiated" do
        idp_initiated
        expect_refused(I18n.t("saml.denial.not_allowed"))

        sp_initiated
        expect_refused(I18n.t("saml.denial.not_allowed"))
      end
    end
  end

  describe "an SP with no restrictions" do
    it "posts an assertion for anyone signed in" do
      idp_initiated
      expect_assertion_posted

      sp_initiated
      expect_assertion_posted
    end
  end
end
