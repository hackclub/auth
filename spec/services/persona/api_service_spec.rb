require "rails_helper"
require "webmock/rspec"

RSpec.describe Persona::APIService do
  let(:api_key) { "persona_sandbox_abc123" }
  let(:service) { described_class.new(api_key: api_key) }
  let(:base_url) { "https://withpersona.com" }

  let(:expected_headers) do
    {
      "Authorization" => "Bearer #{api_key}",
      "Persona-Version" => "2025-12-08",
      "Key-Inflection" => "snake"
    }
  end

  describe "#create_inquiry" do
    it "sends correct params and headers, returns Inquiry" do
      stub_request(:post, "#{base_url}/api/v1/inquiries")
        .with(
          headers: expected_headers,
          body: hash_including(
            "data" => { "attributes" => { "inquiry_template_id" => "tmpl_xxx" } },
            "meta" => hash_including(
              "auto_create_account" => true,
              "auto_create_account_reference_id" => "ident_abc",
              "auto_create_inquiry_session" => true
            )
          )
        )
        .to_return(
          status: 201,
          headers: { "Content-Type" => "application/json" },
          body: { data: inquiry_response_data, included: inquiry_included_data }.to_json
        )

      result = service.create_inquiry(template_id: "tmpl_xxx", account_reference_id: "ident_abc")

      expect(result).to be_a(Persona::Inquiry)
      expect(result.id).to eq("inq_abc123")
      expect(result.status).to eq("created")
      expect(result.account_id).to eq("act_xyz789")
      expect(result.session_token).to eq("session_tok_secret")
    end

    it "raises Persona::APIError on non-2xx response" do
      stub_request(:post, "#{base_url}/api/v1/inquiries")
        .to_return(
          status: 422,
          headers: { "Content-Type" => "application/json" },
          body: { errors: [{ title: "Invalid template" }] }.to_json
        )

      expect {
        service.create_inquiry(template_id: "bad", account_reference_id: "ident_abc")
      }.to raise_error(Persona::APIError, /Invalid template/)
    end
  end

  describe "#retrieve_inquiry" do
    it "returns an Inquiry with full details" do
      stub_request(:get, "#{base_url}/api/v1/inquiries/inq_abc123")
        .with(headers: expected_headers)
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: { data: inquiry_response_data, included: inquiry_included_data }.to_json
        )

      result = service.retrieve_inquiry("inq_abc123")

      expect(result).to be_a(Persona::Inquiry)
      expect(result.id).to eq("inq_abc123")
      expect(result.status).to eq("created")
    end

    it "raises on 404" do
      stub_request(:get, "#{base_url}/api/v1/inquiries/inq_nope")
        .to_return(
          status: 404,
          headers: { "Content-Type" => "application/json" },
          body: { errors: [{ title: "Not found" }] }.to_json
        )

      expect {
        service.retrieve_inquiry("inq_nope")
      }.to raise_error(Persona::APIError, /Not found/)
    end
  end

  describe "#retrieve_government_id_verification" do
    it "returns a GovernmentIdVerification with parsed fields" do
      stub_request(:get, "#{base_url}/api/v1/verification/government-ids/ver_gov123")
        .with(headers: expected_headers)
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: { data: gov_id_verification_data }.to_json
        )

      result = service.retrieve_government_id_verification("ver_gov123")

      expect(result).to be_a(Persona::GovernmentIdVerification)
      expect(result.name_first).to eq("HEIDI")
      expect(result.name_last).to eq("TRASHWORTH")
      expect(result.birthdate).to eq(Date.parse("2005-06-15"))
      expect(result.country_code).to eq("US")
      expect(result.front_photo).to include("url")
      expect(result.back_photo).to include("url")
    end
  end

  describe "#download_file" do
    it "returns binary IO data" do
      fake_image = "\x89PNG\r\n\x1a\n" + ("x" * 100)

      stub_request(:get, "#{base_url}/api/v1/files/some_file_id")
        .with(headers: expected_headers)
        .to_return(status: 200, body: fake_image, headers: { "Content-Type" => "image/png" })

      result = service.download_file("some_file_id")

      expect(result).to respond_to(:read)
      expect(result.read).to include("PNG")
    end
  end

  private

  def inquiry_response_data
    {
      type: "inquiry",
      id: "inq_abc123",
      attributes: {
        status: "created",
        reference_id: "ident_abc",
        created_at: "2026-04-09T12:00:00Z"
      },
      relationships: {
        account: {
          data: { type: "account", id: "act_xyz789" }
        }
      }
    }
  end

  def inquiry_included_data
    [
      {
        type: "inquiry-session",
        id: "iqse_session1",
        attributes: {
          status: "active",
          session_token: "session_tok_secret"
        }
      }
    ]
  end

  def gov_id_verification_data
    {
      type: "verification/government-id",
      id: "ver_gov123",
      attributes: {
        status: "passed",
        name_first: "HEIDI",
        name_last: "TRASHWORTH",
        birthdate: "2005-06-15",
        address_country_code: "US",
        front_photo: { filename: "front.jpg", url: "https://files.withpersona.com/front.jpg", byte_size: 12345 },
        back_photo: { filename: "back.jpg", url: "https://files.withpersona.com/back.jpg", byte_size: 12345 },
        selfie_photo: nil
      }
    }
  end
end
