require "rails_helper"
require_relative "../../support/shared_examples/verification_interface"
require_relative "../../support/shared_examples/rejectable"

RSpec.describe Verification::DocumentVerification, type: :model do
  let(:identity) { create(:identity) }
  let(:document) { create(:identity_document, identity: identity) }

  subject { build(:document_verification, identity: identity, identity_document: document) }

  it_behaves_like "a verification type"
  it_behaves_like "a rejectable verification"

  describe "#relevant_record" do
    it "returns the identity document" do
      expect(subject.relevant_record).to eq(document)
    end
  end

  describe "#document_type_label" do
    it "returns the document's friendly name" do
      expect(subject.document_type_label).to be_a(String)
    end
  end

  describe "#needs_break_glass?" do
    it "returns true" do
      expect(subject.needs_break_glass?).to be true
    end
  end
end
