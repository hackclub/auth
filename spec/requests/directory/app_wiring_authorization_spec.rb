# frozen_string_literal: true

require "rails_helper"

RSpec.describe "App wiring authorization", type: :request do
  def sign_in(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  def grant!(person, collection, permission)
    grantee = create(:directory_group, slug: "g-#{person.id}-#{permission.tr('_', '-')}")
    Directory.mutate!(cause: "test") do
      Directory::Membership.create!(collection: grantee, member_person: person, created_by_identity_id: person.identity_id)
      Directory::Grant.create!(grantee_group: grantee, target_collection: collection, permission: permission, created_by_identity_id: person.identity_id)
    end
  end

  let(:entitlement) { create(:directory_entitlement, slug: "docs-access") }
  let(:owner) { create(:identity) }
  let(:oauth_app) { create(:program, :with_groups, owner_identity: owner) }

  let(:admin) do
    create(:identity).tap do |i|
      create(:backend_user, identity: i, directory_services_admin: true)
      i.reload
    end
  end

  def wire! = post(directory_exposures_path, params: { app_id: oauth_app.id, entitlement_slug: entitlement.slug, claim_name: "docs" })
  def require! = post(directory_app_requirements_path, params: { app_id: oauth_app.id, entitlement_slug: entitlement.slug })

  def unwire!
    # may predate the app losing its groups scope or official status
    exposure = Directory::Exposure.new(app: oauth_app, entitlement: entitlement, claim_name: "docs").tap { |e| e.save!(validate: false) }
    delete directory_exposure_path(exposure)
  end

  def unrequire!
    Directory::AppRequirement.create!(app: oauth_app, entitlement: entitlement)
    delete directory_app_requirement_path(entitlement.slug), params: { app_id: oauth_app.id }
  end

  shared_examples "can do both" do
    it "wires and unwires exposures" do
      expect { wire! }.to change(Directory::Exposure, :count).by(1)
      Directory::Exposure.delete_all
      unwire!
      expect(Directory::Exposure.count).to eq(0)
    end

    it "adds and removes requirements" do
      expect { require! }.to change(Directory::AppRequirement, :count).by(1)
      Directory::AppRequirement.delete_all
      unrequire!
      expect(Directory::AppRequirement.count).to eq(0)
    end
  end

  shared_examples "can do neither" do
    it "can't wire or unwire exposures" do
      expect { wire! }.not_to change(Directory::Exposure, :count)
      unwire!
      expect(Directory::Exposure.count).to eq(1)
    end

    it "can't add or remove requirements" do
      expect { require! }.not_to change(Directory::AppRequirement, :count)
      unrequire!
      expect(Directory::AppRequirement.count).to eq(1)
    end
  end

  context "directory admin who doesn't own the app" do
    before { sign_in admin }

    include_examples "can do both"
  end

  context "app owner with expose on the entitlement" do
    before do
      grant!(create(:directory_person, identity: owner), entitlement, "expose")
      sign_in owner
    end

    include_examples "can do both"

    it "checks wired rows without a query per row" do
      count_queries = lambda do
        n = 0
        counter = ->(*, payload) { n += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get developer_app_path(oauth_app) }
        n
      end
      Directory::Exposure.create!(app: oauth_app, entitlement: entitlement, claim_name: "docs")
      count_queries.call # warm up
      one = count_queries.call
      5.times { |i| Directory::Exposure.create!(app: oauth_app, entitlement: create(:directory_entitlement, slug: "extra-#{i}"), claim_name: "extra#{i}") }

      expect(count_queries.call).to eq(one)
    end

    it "picks from the entitlements it can expose, with their descriptions" do
      entitlement.update!(description: "docs for staff")
      other = create(:directory_entitlement, slug: "not-mine", name: "Not Mine")

      get developer_app_path(oauth_app)

      options = response.parsed_body.css('select[name="entitlement_slug"] option').map { |o| [ o.text, o["value"] ] }
      expect(options).to include([ "#{entitlement.name}: docs for staff", "docs-access" ])
      expect(options.map(&:last)).not_to include(other.slug)
    end

    it "sees the wiring forms and remove buttons" do
      exposure = Directory::Exposure.create!(app: oauth_app, entitlement: entitlement, claim_name: "docs")
      get developer_app_path(oauth_app)

      expect(response.body).to include(directory_exposures_path)
      expect(response.body).to include(directory_exposure_path(exposure))
    end
  end

  context "app owner without expose" do
    before { sign_in owner }

    it "doesn't see descriptions of wired entitlements it can't see in the directory" do
      entitlement.update!(description: "board-only tooling")
      Directory::AppRequirement.create!(app: oauth_app, entitlement: entitlement)

      get developer_app_path(oauth_app)

      expect(response.body).to include(entitlement.name)
      expect(response.body).not_to include("board-only tooling")
    end

    include_examples "can do neither"

    it "doesn't see the wiring forms or remove buttons" do
      Directory::Exposure.create!(app: oauth_app, entitlement: entitlement, claim_name: "docs")
      get developer_app_path(oauth_app)

      expect(response.body).to include("docs")
      expect(response.body).not_to include(directory_exposures_path)
      expect(response.body).not_to include(directory_app_requirements_path)
      expect(response.body).not_to include(directory_exposure_path(Directory::Exposure.last))
    end
  end

  context "someone who can't see the entitlement" do
    before { sign_in owner }

    it "gets the same 404 for an existing exposure as for a missing id" do
      exposure = Directory::Exposure.create!(app: oauth_app, entitlement: entitlement, claim_name: "docs")

      delete directory_exposure_path(exposure)
      expect(response).to have_http_status(:not_found)
      delete directory_exposure_path(exposure.id + 1000)
      expect(response).to have_http_status(:not_found)
      expect(Directory::Exposure.exists?(exposure.id)).to be(true)
    end
  end

  context "expose holder who doesn't own the app" do
    before do
      someone = create(:identity)
      grant!(create(:directory_person, identity: someone), entitlement, "expose")
      sign_in someone
    end

    include_examples "can do neither"
  end

  context "app that isn't hq_official" do
    let(:oauth_app) { create(:program, owner_identity: owner, trust_level: :community_untrusted, scopes: "openid profile") }

    before { sign_in admin }

    it "can't get new wiring, but existing wiring can still be removed" do
      expect { wire! }.not_to change(Directory::Exposure, :count)
      expect { require! }.not_to change(Directory::AppRequirement, :count)

      unwire!
      unrequire!
      expect(Directory::Exposure.count).to eq(0)
      expect(Directory::AppRequirement.count).to eq(0)
    end
  end
end
