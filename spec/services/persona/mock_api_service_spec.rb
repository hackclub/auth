require "rails_helper"

RSpec.describe Persona::MockAPIService do
  let(:service) { described_class.new }

  describe "shape parity with APIService" do
    it "create_inquiry returns a Persona::Inquiry with all fields" do
      result = service.create_inquiry(template_id: "itmpl_test", account_reference_id: "ident_abc")

      expect(result).to be_a(Persona::Inquiry)
      expect(result.id).to start_with("inq_")
      expect(result.status).to eq("created")
      expect(result.account_id).to start_with("act_")
      expect(result.session_token).to start_with("session_tok_")
      expect(result.verification_ids).to be_an(Array)
      expect(result.verification_ids.first).to have_key(:type)
      expect(result.verification_ids.first).to have_key(:id)
    end

    it "retrieve_inquiry returns a completed inquiry" do
      result = service.retrieve_inquiry("inq_test123")

      expect(result).to be_a(Persona::Inquiry)
      expect(result.id).to eq("inq_test123")
      expect(result.status).to eq("completed")
      expect(result.account_id).to be_present
      expect(result.verification_ids).to be_an(Array)
    end

    it "resume_inquiry returns an inquiry with a fresh session token" do
      result = service.resume_inquiry("inq_test123")

      expect(result).to be_a(Persona::Inquiry)
      expect(result.id).to eq("inq_test123")
      expect(result.session_token).to start_with("session_tok_")
    end

    it "retrieve_government_id_verification returns all required fields" do
      result = service.retrieve_government_id_verification("ver_gov123")

      expect(result).to be_a(Persona::GovernmentIdVerification)
      expect(result.name_first).to be_a(String)
      expect(result.name_last).to be_a(String)
      expect(result.birthdate).to be_a(Date)
      expect(result.country_code).to be_a(String)
      expect(result.front_photo).to have_key(:url)
      expect(result.front_photo).to have_key(:filename)
      expect(result.back_photo).to have_key(:url)
    end

    it "download_file returns an IO-like object" do
      result = service.download_file("https://example.com/photo.jpg")

      expect(result).to respond_to(:read)
      expect(result.read).to be_a(String)
      expect(result.read.length).to be >= 0 # not empty after read — rewind
    end

    it "create_inquiry generates deterministic account IDs for the same reference" do
      r1 = service.create_inquiry(template_id: "t", account_reference_id: "ident_abc")
      r2 = service.create_inquiry(template_id: "t", account_reference_id: "ident_abc")

      expect(r1.account_id).to eq(r2.account_id)
    end

    it "create_inquiry generates different account IDs for different references" do
      r1 = service.create_inquiry(template_id: "t", account_reference_id: "ident_abc")
      r2 = service.create_inquiry(template_id: "t", account_reference_id: "ident_xyz")

      expect(r1.account_id).not_to eq(r2.account_id)
    end

    it "create_inquiry generates unique inquiry IDs" do
      ids = 5.times.map {
        service.create_inquiry(template_id: "t", account_reference_id: "ident_abc").id
      }

      expect(ids.uniq.length).to eq(5)
    end
  end

  describe "gov_id_verification_id helper" do
    it "extracts government ID verification from verification_ids" do
      inquiry = service.create_inquiry(template_id: "t", account_reference_id: "ident_abc")

      gov_id_ver = inquiry.verification_ids.find { |v| v[:type] == "verification/government-id" }
      expect(gov_id_ver).to be_present
      expect(gov_id_ver[:id]).to start_with("ver_gov_test_")
    end
  end
end
