require "rails_helper"
require_relative "../../support/shared_examples/verification_interface"

RSpec.describe Verification::VouchVerification, type: :model do
  let(:identity) { create(:identity) }

  subject { build(:vouch_verification, identity: identity) }

  it_behaves_like "a verification type"

  describe "#relevant_record" do
    it "returns nil" do
      expect(subject.relevant_record).to be_nil
    end
  end

  describe "#document_type_label" do
    it "returns Vouch" do
      expect(subject.document_type_label).to eq("Vouch")
    end
  end

  describe "#needs_break_glass?" do
    it "returns false" do
      expect(subject.needs_break_glass?).to be false
    end
  end

  describe "#rejection_reason_options" do
    it "returns empty groups" do
      options = subject.rejection_reason_options
      expect(options[:retryable]).to be_empty
      expect(options[:fatal]).to be_empty
    end
  end
end
