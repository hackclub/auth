require "rails_helper"

RSpec.describe VerificationCasePolicy do
  let(:verifier) { create(:backend_user, manual_document_verifier: true) }
  let(:super_admin) { create(:backend_user, super_admin: true) }
  let(:pleb) { create(:backend_user) }

  describe "case management" do
    let(:kase) { create(:verification_case, :call_held) }

    it "allows manual document verifiers" do
      expect(described_class.new(verifier, kase).create?).to be(true)
      expect(described_class.new(verifier, kase).show?).to be(true)
      expect(described_class.new(verifier, kase).decide?).to be(true)
    end

    it "denies users without the role" do
      expect(described_class.new(pleb, kase).show?).to be(false)
      expect(described_class.new(pleb, kase).decide?).to be(false)
    end
  end

  describe "comments" do
    let(:kase) { create(:verification_case, :call_held) }

    it "allows verifiers and denies others" do
      expect(described_class.new(verifier, kase).comment?).to be(true)
      expect(described_class.new(pleb, kase).comment?).to be(false)
    end
  end
end
