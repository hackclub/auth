require "rails_helper"

RSpec.describe OAuthScope do
  describe "ALL" do
    it "contains all expected scopes" do
      scope_names = described_class::ALL.map(&:name)
      expect(scope_names).to contain_exactly(
        "openid", "email", "name", "profile", "phone", "birthdate",
        "address", "verification_status", "slack_id", "legal_name",
        "basic_info", "set_slack_id"
      )
    end

    it "each scope has a name and description" do
      described_class::ALL.each do |scope|
        expect(scope.name).to be_present, "Scope missing name"
        expect(scope.description).to be_present, "Scope #{scope.name} missing description"
      end
    end
  end

  describe ".find" do
    it "returns the scope by name" do
      scope = described_class.find("email")
      expect(scope).to be_a(described_class)
      expect(scope.name).to eq("email")
    end

    it "returns nil for unknown scope" do
      expect(described_class.find("unknown")).to be_nil
    end

    it "accepts symbols" do
      expect(described_class.find(:email)).to eq(described_class.find("email"))
    end
  end

  describe ".known?" do
    it "returns true for known scopes" do
      expect(described_class.known?("email")).to be true
      expect(described_class.known?("basic_info")).to be true
    end

    it "returns false for unknown scopes" do
      expect(described_class.known?("unknown")).to be false
    end
  end

  describe ".consent_fields_for" do
    let(:address) { build_stubbed(:address, line_1: "123 Main St", city: "Burlington", state: "VT", country: "US") }
    let(:identity) do
      build_stubbed(:identity).tap { |i| allow(i).to receive(:primary_address).and_return(address) }
    end

    it "returns fields for email scope" do
      fields = described_class.consent_fields_for(%w[email], identity)
      expect(fields).to contain_exactly(
        a_hash_including(key: :email, value: identity.primary_email)
      )
    end

    it "returns fields for name scope" do
      fields = described_class.consent_fields_for(%w[name], identity)
      expect(fields).to contain_exactly(
        a_hash_including(key: :name, value: "#{identity.first_name} #{identity.last_name}")
      )
    end

    it "returns fields for verification_status scope" do
      fields = described_class.consent_fields_for(%w[verification_status], identity)
      expect(fields).to contain_exactly(
        a_hash_including(key: :verification_status, value: identity.verification_status),
        a_hash_including(key: :ysws_eligible, value: "Yes")
      )
    end

    it "returns fields for address scope" do
      fields = described_class.consent_fields_for(%w[address], identity)
      expect(fields.first[:key]).to eq(:address)
      expect(fields.first[:value]).to include(identity.primary_address.city)
    end

    it "returns fields for legal_name scope" do
      fields = described_class.consent_fields_for(%w[legal_name], identity)
      expect(fields).to contain_exactly(
        a_hash_including(key: :legal_name, value: "#{identity.legal_first_name} #{identity.legal_last_name}")
      )
    end

    it "expands basic_info to include all its sub-scopes" do
      fields = described_class.consent_fields_for(%w[basic_info], identity)
      keys = fields.map { |f| f[:key] }
      expect(keys).to include(:email, :name, :slack_id, :phone, :birthdate, :verification_status, :ysws_eligible)
    end

    it "deduplicates fields when scopes overlap" do
      fields = described_class.consent_fields_for(%w[email basic_info], identity)
      email_fields = fields.select { |f| f[:key] == :email }
      expect(email_fields.size).to eq(1)
    end

    it "deduplicates fields when name and profile both requested" do
      fields = described_class.consent_fields_for(%w[name profile], identity)
      name_fields = fields.select { |f| f[:key] == :name }
      expect(name_fields.size).to eq(1)
    end

    it "returns empty array for openid-only scope" do
      fields = described_class.consent_fields_for(%w[openid], identity)
      expect(fields).to be_empty
    end

    it "ignores unknown scopes" do
      fields = described_class.consent_fields_for(%w[unknown email], identity)
      expect(fields).to contain_exactly(
        a_hash_including(key: :email)
      )
    end
  end

  describe ".expanded_scopes" do
    it "returns the scope itself for simple scopes" do
      scopes = described_class.expanded_scopes(%w[email])
      expect(scopes.map(&:name)).to eq(%w[email])
    end

    it "expands basic_info to include referenced scopes" do
      scopes = described_class.expanded_scopes(%w[basic_info])
      names = scopes.map(&:name)
      expect(names).to include("basic_info", "email", "name", "slack_id", "phone", "birthdate", "verification_status")
    end
  end

  describe "COMMUNITY_ALLOWED" do
    it "contains only safe scopes for community apps" do
      expect(described_class::COMMUNITY_ALLOWED).to contain_exactly(
        "openid", "profile", "email", "name", "slack_id", "verification_status"
      )
    end
  end
end
