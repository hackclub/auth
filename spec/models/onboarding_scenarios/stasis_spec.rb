require "rails_helper"

RSpec.describe OnboardingScenarios::Stasis do
  let(:identity) { create(:identity) }
  let(:scenario) { described_class.new(identity) }

  describe ".slug" do
    it "returns 'stasis'" do
      expect(described_class.slug).to eq("stasis")
    end
  end

  describe "#title" do
    it "returns the Austin join message" do
      expect(scenario.title).to eq("Ready to join us in Austin?")
    end
  end

  describe "#form_fields" do
    it "includes expected fields" do
      expect(scenario.form_fields).to contain_exactly(
        :first_name, :last_name, :primary_email, :birthday, :country
      )
    end
  end

  describe "#next_action" do
    it "returns :slack" do
      expect(scenario.next_action).to eq(:slack)
    end
  end
end
