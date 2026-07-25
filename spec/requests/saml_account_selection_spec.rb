require "rails_helper"

RSpec.describe "SAML account selection", type: :request do
  let(:allowed) { create(:identity, primary_email: "nora@hackclub.com") }
  let(:also_allowed) { create(:identity, primary_email: "max@hackclub.com") }
  let(:disallowed) { create(:identity, primary_email: "nora@example.com") }
  let(:sp_config) do
    {
      slug: "airtable",
      entity_id: "https://airtable.example/saml",
      allow_idp_initiated: true,
      allowed_emails: [ allowed.primary_email, also_allowed.primary_email ]
    }
  end

  before do
    Flipper.enable(BrowserAccountsController::FEATURE_FLAG)
    Flipper.enable(:are_we_enterprise_yet_2025_10_21)
    allow_any_instance_of(SAMLController).to receive(:ensure_sp_configured!) do |controller|
      controller.instance_variable_set(:@sp_config, sp_config)
      true
    end
  end

  after do
    Flipper.disable(BrowserAccountsController::FEATURE_FLAG)
    Flipper.disable(:are_we_enterprise_yet_2025_10_21)
  end

  it "offers eligible siblings before rejecting a disallowed active account" do
    sign_in_as(allowed)
    add_account(also_allowed)
    add_account(disallowed)

    post idp_initiated_saml_path(slug: "airtable")

    expect(response).to have_http_status(:ok)
    offered_emails = Nokogiri::HTML(response.body).css(".account-email").map(&:text).map(&:strip)
    expect(offered_emails).to contain_exactly(allowed.primary_email, also_allowed.primary_email)
  end

  it "uses the sole eligible sibling instead of the disallowed active account" do
    sign_in_as(allowed)
    add_account(disallowed)

    allow_any_instance_of(SAMLController).to receive(:build_saml_response).and_return(Object.new)
    allow_any_instance_of(SAMLController).to receive(:render_saml_response) do |controller, **kwargs|
      controller.render plain: kwargs.fetch(:identity).primary_email
    end

    post idp_initiated_saml_path(slug: "airtable")

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq(allowed.primary_email)
  end
end
