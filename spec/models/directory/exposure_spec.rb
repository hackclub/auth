# frozen_string_literal: true

require "rails_helper"

RSpec.describe Directory::Exposure do
  let(:entitlement) { create(:directory_entitlement) }

  it "refuses an app that doesn't request the groups scope" do
    exposure = described_class.new(app: create(:program, trust_level: :hq_official), entitlement: entitlement, claim_name: "staff")

    expect(exposure).not_to be_valid
    expect(exposure.errors[:base].join).to include("groups scope")
  end

  it "accepts an app that does" do
    expect(described_class.new(app: create(:program, :with_groups), entitlement: entitlement, claim_name: "staff")).to be_valid
  end
end
