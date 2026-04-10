require "rails_helper"

RSpec.describe Persona::APIService do
  let(:api_key) { "persona_sandbox_abc123" }
  let(:service) { described_class.new(api_key: api_key) }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:connection) do
    Faraday.new do |f|
      f.request :json
      f.response :json
      f.adapter :test, stubs
    end
  end

  before do
    allow(service).to receive(:connection).and_return(connection)
  end

  after { stubs.verify_stubbed_calls }

  describe "request headers" do
    it "sets Bearer authorization" do
      stubs.post("/api/v1/inquiries") do |env|
        expect(env.request_headers["Authorization"]).to eq("Bearer #{api_key}")
        [201, {}, { "data" => inquiry_response_data }]
      end

      service.create_inquiry(template_id: "tmpl_xxx", account_reference_id: "ident_abc")
    end

    it "sets Persona-Version header" do
      stubs.post("/api/v1/inquiries") do |env|
        expect(env.request_headers["Persona-Version"]).to eq("2025-12-08")
        [201, {}, { "data" => inquiry_response_data }]
      end

      service.create_inquiry(template_id: "tmpl_xxx", account_reference_id: "ident_abc")
    end

    it "sets Key-Inflection to snake_case" do
      stubs.post("/api/v1/inquiries") do |env|
        expect(env.request_headers["Key-Inflection"]).to eq("snake")
        [201, {}, { "data" => inquiry_response_data }]
      end

      service.create_inquiry(template_id: "tmpl_xxx", account_reference_id: "ident_abc")
    end
  end

  describe "#create_inquiry" do
    it "sends correct params with auto-create-account-reference-id" do
      stubs.post("/api/v1/inquiries") do |env|
        body = JSON.parse(env.body)
        expect(body.dig("data", "attributes", "inquiry_template_id")).to eq("tmpl_xxx")
        expect(body.dig("meta", "auto_create_account")).to be true
        expect(body.dig("meta", "auto_create_account_reference_id")).to eq("ident_abc")
        expect(body.dig("meta", "auto_create_inquiry_session")).to be true
        [201, {}, { "data" => inquiry_response_data, "included" => inquiry_included_data }]
      end

      result = service.create_inquiry(template_id: "tmpl_xxx", account_reference_id: "ident_abc")

      expect(result).to be_a(Persona::Inquiry)
      expect(result.id).to eq("inq_abc123")
      expect(result.status).to eq("created")
      expect(result.account_id).to eq("act_xyz789")
      expect(result.session_token).to eq("session_tok_secret")
    end

    it "raises on non-2xx response" do
      stubs.post("/api/v1/inquiries") do
        [422, {}, { "errors" => [{ "title" => "Invalid template" }] }]
      end

      expect {
        service.create_inquiry(template_id: "bad", account_reference_id: "ident_abc")
      }.to raise_error(Persona::APIError)
    end
  end

  describe "#retrieve_inquiry" do
    it "returns an Inquiry with full details" do
      stubs.get("/api/v1/inquiries/inq_abc123") do
        [200, {}, { "data" => inquiry_response_data, "included" => inquiry_included_data }]
      end

      result = service.retrieve_inquiry("inq_abc123")

      expect(result).to be_a(Persona::Inquiry)
      expect(result.id).to eq("inq_abc123")
    end

    it "raises on 404" do
      stubs.get("/api/v1/inquiries/inq_nope") do
        [404, {}, { "errors" => [{ "title" => "Not found" }] }]
      end

      expect {
        service.retrieve_inquiry("inq_nope")
      }.to raise_error(Persona::APIError)
    end
  end

  describe "#retrieve_government_id_verification" do
    it "returns a GovernmentIdVerification" do
      stubs.get("/api/v1/verification/government-ids/ver_gov123") do
        [200, {}, { "data" => gov_id_verification_data }]
      end

      result = service.retrieve_government_id_verification("ver_gov123")

      expect(result).to be_a(Persona::GovernmentIdVerification)
      expect(result.name_first).to eq("HEIDI")
      expect(result.name_last).to eq("TRASHWORTH")
      expect(result.birthdate).to eq(Date.parse("2005-06-15"))
      expect(result.country_code).to eq("US")
    end
  end

  describe "#download_file" do
    it "returns binary IO data" do
      fake_image = "\x89PNG\r\n\x1a\n" + ("x" * 100)
      stubs.get("/api/v1/files/some_file_id") do
        [200, { "Content-Type" => "image/png" }, fake_image]
      end

      result = service.download_file("some_file_id")

      expect(result).to respond_to(:read)
    end
  end

  private

  def inquiry_response_data
    {
      "type" => "inquiry",
      "id" => "inq_abc123",
      "attributes" => {
        "status" => "created",
        "reference_id" => "ident_abc",
        "created_at" => "2026-04-09T12:00:00Z"
      },
      "relationships" => {
        "account" => {
          "data" => { "type" => "account", "id" => "act_xyz789" }
        }
      }
    }
  end

  def inquiry_included_data
    [
      {
        "type" => "inquiry-session",
        "id" => "iqse_session1",
        "attributes" => {
          "status" => "active",
          "session_token" => "session_tok_secret"
        }
      }
    ]
  end

  def gov_id_verification_data
    {
      "type" => "verification/government-id",
      "id" => "ver_gov123",
      "attributes" => {
        "status" => "passed",
        "name_first" => "HEIDI",
        "name_last" => "TRASHWORTH",
        "birthdate" => "2005-06-15",
        "address_country_code" => "US",
        "front_photo" => { "filename" => "front.jpg", "url" => "https://files.withpersona.com/front.jpg", "byte_size" => 12345 },
        "back_photo" => { "filename" => "back.jpg", "url" => "https://files.withpersona.com/back.jpg", "byte_size" => 12345 },
        "selfie_photo" => nil
      }
    }
  end
end
