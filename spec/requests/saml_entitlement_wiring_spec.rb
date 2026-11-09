# frozen_string_literal: true

require "rails_helper"
require_relative "../support/saml_test_helpers"

RSpec.describe "SAML SPs and directory entitlements", type: :request do
  include SAMLTestHelpers

  let(:identity) { create(:identity) }

  def sp_entry(slug, **settings)
    {
      slug: slug,
      friendly_name: slug.titleize,
      entity_id: "https://#{slug}.example.test/metadata",
      allow_idp_initiated: true,
      assertion_consumer_services: [ { location: "https://#{slug}.example.test/acs", binding: SAMLTestHelpers::HTTP_POST_BINDING } ],
      attribute_consuming_services: [
        { name: "Profile", requested_attributes: [ { name: "email" }, { name: "groups" } ] }
      ]
    }.merge(settings)
  end

  describe "home page SSO tiles" do
    before do
      entitlement!("gated-users")
      use_saml_service_providers(
        sp_entry("open-sp"),
        sp_entry("gated-sp", required_entitlements: [ "gated-users" ])
      )
      allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
      allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
    end

    it "hides SPs the identity can't log in to" do
      get root_path

      expect(response.body).to include("Open Sp")
      expect(response.body).not_to include("Gated Sp")
    end

    it "shows them once the identity holds a required entitlement" do
      add_member!(Directory::Collection.find_by!(slug: "gated-users"), identity: identity)

      get root_path

      expect(response.body).to include("Gated Sp")
    end
  end

  describe "entitlements referenced in config/saml.yml" do
    let!(:required) { entitlement!("required-ent") }
    let!(:grouped) { entitlement!("grouped-ent") }
    let!(:unused) { entitlement!("unused-ent") }

    before do
      use_saml_service_providers(
        sp_entry("gated-sp", required_entitlements: [ "required-ent" ]),
        sp_entry("grouping-sp", entitlements: { "grouped-ent": "staff" })
      )
    end

    it "can't be deleted" do
      expect { required.destroy }.not_to change(Directory::Collection, :count)
      expect(required.errors[:base].join).to include("Gated Sp")

      expect(grouped.destroy).to be(false)
      expect(unused.destroy).to be_truthy
    end

    it "keeps its memberships when the delete is refused" do
      add_member!(required, identity: identity)

      required.destroy

      expect(required.memberships.reload).not_to be_empty
    end

    it "refuses the delete from the directory UI with a flash" do
      admin = create(:identity)
      create(:backend_user, identity: admin, directory_services_admin: true)
      allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(admin.reload)
      allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)

      delete directory_collection_path(required.slug)

      expect(response).to redirect_to(directory_collection_path(required.slug))
      expect(flash[:alert]).to include("Gated Sp")
      expect(Directory::Collection.exists?(required.id)).to be(true)
    end

    it "can't be renamed to a different slug" do
      expect(required.update(slug: "renamed")).to be(false)
      expect(required.errors[:slug].join).to include("Gated Sp")
      expect(required.reload.update(name: "Renamed")).to be(true)
    end
  end
end
