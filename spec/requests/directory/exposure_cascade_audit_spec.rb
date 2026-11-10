# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Exposures removed by a cascade", type: :request do
  let(:admin) do
    create(:identity).tap do |i|
      create(:backend_user, identity: i, directory_services_admin: true)
      i.reload
    end
  end
  let(:oauth_app) { create(:program, :with_groups, name: "Wired App") }
  let(:entitlement) { create(:directory_entitlement, slug: "staff", name: "Staff") }
  let!(:exposure) { Directory::Exposure.create!(app: oauth_app, entitlement: entitlement, claim_name: "staff") }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(admin)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  def unwire_activity = PublicActivity::Activity.find_by(trackable_type: "Directory::Exposure", trackable_id: exposure.id, key: "directory_exposure.destroy")

  it "logs the unwire when the entitlement is deleted" do
    delete directory_collection_path(entitlement.slug)

    expect(Directory::Exposure.exists?(exposure.id)).to be(false)
    expect(unwire_activity).to be_present
    expect(unwire_activity.owner).to eq(admin)
    expect(unwire_activity.parameters).to include("app_name" => "Wired App", "entitlement_name" => "Staff")
  end

  it "logs the unwire when the app is deleted" do
    oauth_app.destroy!

    expect(unwire_activity).to be_present
    expect(unwire_activity.parameters).to include("app_name" => "Wired App")
  end
end
