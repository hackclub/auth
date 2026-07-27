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

  describe "escalated cases" do
    let(:kase) { create(:verification_case, :escalated) }

    it "blocks the escalating reviewer from resolving their own escalation" do
      kase.log_event!(:escalated, actor: verifier)
      expect(described_class.new(verifier, kase).decide?).to be(false)
    end

    it "allows a different verifier to resolve" do
      other = create(:backend_user, manual_document_verifier: true)
      kase.log_event!(:escalated, actor: other)
      expect(described_class.new(verifier, kase).decide?).to be(true)
    end

    it "always allows super admins" do
      kase.log_event!(:escalated, actor: super_admin)
      expect(described_class.new(super_admin, kase).decide?).to be(true)
    end
  end
end
