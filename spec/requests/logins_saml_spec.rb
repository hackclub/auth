# frozen_string_literal: true

require "rails_helper"
require_relative "../support/saml_test_helpers"

# Signups whose scenario sends them to Slack are logged straight into it once their code is
# verified: LoginsController#render_saml_response_for builds and posts the Slack assertion
# itself, without going through SAMLController.
RSpec.describe "SAML login straight after verifying a login code", type: :request do
  include SAMLTestHelpers

  let(:slack_acs_url) { "https://slack.example.test/sso/saml" }
  let(:slack_settings) { {} }
  # the factory gives every identity a slack_id, which keeps SCIM provisioning out of this
  let(:identity) { create(:identity) }

  before do
    use_saml_service_providers({
      slug: "slack",
      friendly_name: "Hack Club Slack",
      entity_id: "https://slack.example.test",
      allow_idp_initiated: true,
      assertion_consumer_services: [ { location: slack_acs_url, binding: SAMLTestHelpers::HTTP_POST_BINDING } ],
      attribute_consuming_services: [
        { name: "Slack User Profile", requested_attributes: [ { name: "User.Email", is_required: true } ] }
      ]
    }.merge(slack_settings))
    stub_saml_signing
    Flipper.enable(:are_we_enterprise_yet_2025_10_21)
  end

  after { Flipper.disable(:are_we_enterprise_yet_2025_10_21) }

  def verify_login_code
    @attempt = LoginAttempt.create!(identity:, authentication_factors: {}, provenance: "signup", next_action: "slack")
    code = Identity::V2LoginCode.generate(identity)
    post verify_login_attempt_path(id: @attempt.to_param), params: { code: code.code }
  end

  def expect_logged_in_without_assertion(message)
    expect(response).to have_http_status(:forbidden)
    expect(response.body).to include(message)
    expect(posted_saml_response).to be_nil
    # the HCA login itself still went through; only the hop into the SP is refused
    expect(@attempt.reload.session).to be_present
  end

  it "posts the Slack assertion when the identity may use Slack" do
    verify_login_code

    expect(response).to have_http_status(:ok)
    expect(saml_post_target).to eq(slack_acs_url)
    expect(posted_name_id).to eq(identity.to_saml_nameid.id)
  end

  context "when the SP requires an entitlement the identity doesn't have" do
    let(:slack_settings) { { required_entitlements: [ "slack-users" ] } }

    before { entitlement!("slack-users") }

    it "shows the SAML error page instead of posting an assertion" do
      verify_login_code

      expect_logged_in_without_assertion(I18n.t("saml.denial.no_access"))
    end
  end

  context "when the SP requires an entitlement that doesn't exist" do
    let(:slack_settings) { { required_entitlements: [ "deleted-entitlement" ] } }

    it "fails closed" do
      verify_login_code

      expect_logged_in_without_assertion(I18n.t("saml.denial.misconfigured"))
    end
  end

  context "when the SP's allowed_emails doesn't list the identity" do
    let(:slack_settings) { { allowed_emails: [ "someone-else@hackclub.com" ] } }

    it "shows the SAML error page instead of posting an assertion" do
      verify_login_code

      expect_logged_in_without_assertion(I18n.t("saml.denial.not_allowed"))
    end
  end

  context "when the identity is barred from Slack" do
    before { identity.update!(disallow_slack: true) }

    it "shows the SAML error page instead of posting an assertion" do
      verify_login_code

      expect_logged_in_without_assertion(I18n.t("saml.denial.disallow_slack"))
    end
  end
end
