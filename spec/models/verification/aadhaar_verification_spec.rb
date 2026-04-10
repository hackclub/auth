require "rails_helper"
require_relative "../../support/shared_examples/verification_interface"

RSpec.describe Verification::AadhaarVerification, type: :model do
  let(:identity) { create(:identity) }

  subject { build(:aadhaar_verification, identity: identity) }

  it_behaves_like "a verification type"

  describe "#relevant_record" do
    it "returns the aadhaar record" do
      expect(subject.relevant_record).to eq(subject.aadhaar_record)
    end
  end

  describe "#document_type_label" do
    it "returns Aadhaar" do
      expect(subject.document_type_label).to eq("Aadhaar")
    end
  end

  describe "#needs_break_glass?" do
    it "returns true" do
      expect(subject.needs_break_glass?).to be true
    end
  end
end
