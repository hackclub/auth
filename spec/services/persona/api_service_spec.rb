require "rails_helper"
require "webmock/rspec"

RSpec.describe Persona::APIService do
  let(:api_key) { "persona_sandbox_abc123" }
  let(:service) { described_class.new(api_key: api_key) }
  let(:base_url) { "https://api.withpersona.com" }

  let(:expected_headers) do
    {
      "Authorization" => "Bearer #{api_key}",
      "Persona-Version" => "2025-12-08",
      "Key-Inflection" => "snake"
    }
  end

  describe "#create_inquiry" do
    it "sends correct params and headers, returns Inquiry with session token from meta" do
      stub_request(:post, "#{base_url}/api/v1/inquiries")
        .with(
          headers: expected_headers,
          body: hash_including(
            "data" => { "attributes" => { "inquiry_template_id" => "itmpl_xxx" } },
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
          body: {
            data: inquiry_response_data,
            included: [],
            meta: { session_token: "session_tok_secret" }
          }.to_json
        )

      result = service.create_inquiry(template_id: "itmpl_xxx", account_reference_id: "ident_abc")

      expect(result).to be_a(Persona::Inquiry)
      expect(result.id).to eq("inq_abc123")
      expect(result.status).to eq("created")
      expect(result.account_id).to eq("act_xyz789")
      expect(result.session_token).to eq("session_tok_secret")
      expect(result.verification_ids).to be_an(Array)
    end

    it "raises Persona::APIError on non-2xx response" do
      stub_request(:post, "#{base_url}/api/v1/inquiries")
        .to_return(
          status: 422,
          headers: { "Content-Type" => "application/json" },
          body: { errors: [ { title: "Invalid template" } ] }.to_json
        )

      expect {
        service.create_inquiry(template_id: "bad", account_reference_id: "ident_abc")
      }.to raise_error(Persona::APIError, /Invalid template/)
    end
  end

  describe "#retrieve_inquiry" do
    it "returns an Inquiry with verification IDs from relationships" do
      stub_request(:get, "#{base_url}/api/v1/inquiries/inq_abc123?include=sessions")
        .with(headers: expected_headers)
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            data: inquiry_response_data,
            included: [],
            meta: {}
          }.to_json
        )

      result = service.retrieve_inquiry("inq_abc123")

      expect(result).to be_a(Persona::Inquiry)
      expect(result.id).to eq("inq_abc123")
      expect(result.status).to eq("created")
      expect(result.gov_id_verification_id).to eq("ver_gov123")
    end

    it "raises on 404" do
      stub_request(:get, "#{base_url}/api/v1/inquiries/inq_nope?include=sessions")
        .to_return(
          status: 404,
          headers: { "Content-Type" => "application/json" },
          body: { errors: [ { title: "Not found" } ] }.to_json
        )

      expect {
        service.retrieve_inquiry("inq_nope")
      }.to raise_error(Persona::APIError, /Not found/)
    end
  end

  describe "#resume_inquiry" do
    it "returns an Inquiry with a fresh session token from meta" do
      stub_request(:post, "#{base_url}/api/v1/inquiries/inq_abc123/resume")
        .with(headers: expected_headers)
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            data: inquiry_response_data,
            meta: { session_token: "fresh_session_tok" }
          }.to_json
        )

      result = service.resume_inquiry("inq_abc123")

      expect(result).to be_a(Persona::Inquiry)
      expect(result.session_token).to eq("fresh_session_tok")
    end

    it "raises ConflictError on 409" do
      stub_request(:post, "#{base_url}/api/v1/inquiries/inq_abc123/resume")
        .to_return(
          status: 409,
          headers: { "Content-Type" => "application/json" },
          body: { errors: [ { title: "Conflict" } ] }.to_json
        )

      expect {
        service.resume_inquiry("inq_abc123")
      }.to raise_error(Persona::ConflictError, /Conflict/)
    end
  end

  describe "#retrieve_government_id_verification" do
    it "returns a GovernmentIdVerification with parsed fields" do
      stub_request(:get, "#{base_url}/api/v1/verification/government-ids/ver_gov123")
        .with(headers: expected_headers)
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: { data: gov_id_verification_data, meta: {} }.to_json
        )

      result = service.retrieve_government_id_verification("ver_gov123")

      expect(result).to be_a(Persona::GovernmentIdVerification)
      expect(result.name_first).to eq("HEIDI")
      expect(result.name_last).to eq("TRASHWORTH")
      expect(result.birthdate).to eq(Date.parse("2005-06-15"))
      expect(result.country_code).to eq("US")
      expect(result.front_photo).to include(:url)
      expect(result.back_photo).to include(:url)
    end
  end

  describe "#retrieve_document_photos" do
    it "returns a PhotoSet with front/back for government-id documents" do
      stub_request(:get, "#{base_url}/api/v1/document/government-ids/doc_gov123")
        .with(headers: expected_headers)
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: { data: { id: "doc_gov123", type: "document/government-id", attributes: {
            front_photo: { filename: "front.jpg", url: "https://files.withpersona.com/front.jpg", byte_size: 12345 },
            back_photo: { filename: "back.jpg", url: "https://files.withpersona.com/back.jpg", byte_size: 12345 }
          } }, meta: {} }.to_json
        )

      result = service.retrieve_document_photos("doc_gov123", type: "document/government-id")

      expect(result).to be_a(Persona::PhotoSet)
      expect(result.document.length).to eq(2)
      expect(result.liveness).to be_empty
    end

    it "returns files array for generic documents" do
      stub_request(:get, "#{base_url}/api/v1/documents/doc_generic")
        .with(headers: expected_headers)
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: { data: { id: "doc_generic", type: "document", attributes: {
            files: [ { url: "https://files.withpersona.com/file1.pdf", filename: "file1.pdf" } ]
          } }, meta: {} }.to_json
        )

      result = service.retrieve_document_photos("doc_generic", type: "document/generic")

      expect(result).to be_a(Persona::PhotoSet)
      expect(result.document.length).to eq(1)
      expect(result.document.first[:label]).to eq("file_1")
    end
  end

  describe "#retrieve_verification_photos" do
    it "returns liveness photos for selfie verifications" do
      stub_request(:get, "#{base_url}/api/v1/verification/selfies/ver_selfie123")
        .with(headers: expected_headers)
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: { data: { id: "ver_selfie123", type: "verification/selfie", attributes: {
            center_photo_url: "https://files.withpersona.com/center.jpg",
            left_photo_url: "https://files.withpersona.com/left.jpg",
            right_photo_url: "https://files.withpersona.com/right.jpg"
          } }, meta: {} }.to_json
        )

      result = service.retrieve_verification_photos("ver_selfie123", type: "verification/selfie")

      expect(result).to be_a(Persona::PhotoSet)
      expect(result.document).to be_empty
      expect(result.liveness.length).to eq(3)
      expect(result.liveness.map { |l| l[:label] }).to contain_exactly("selfie_center", "selfie_left", "selfie_right")
    end

    it "returns empty PhotoSet for non-selfie verifications" do
      result = service.retrieve_verification_photos("ver_gov123", type: "verification/government-id")

      expect(result).to be_a(Persona::PhotoSet)
      expect(result.document).to be_empty
      expect(result.liveness).to be_empty
    end
  end

  describe "#download_file" do
    it "downloads from withpersona.com" do
      file_url = "https://files.withpersona.com/photo.jpg?access_token=tok123"
      fake_image = "\x89PNG\r\n\x1a\n" + ("x" * 100)

      stub_request(:get, file_url)
        .to_return(status: 200, body: fake_image, headers: { "Content-Type" => "image/png" })

      result = service.download_file(file_url)

      expect(result).to respond_to(:read)
      expect(result.read).to include("PNG")
    end

    it "rejects non-https URLs" do
      expect {
        service.download_file("http://files.withpersona.com/photo.jpg")
      }.to raise_error(Persona::APIError, /untrusted host/)
    end

    it "rejects non-persona hosts" do
      expect {
        service.download_file("https://evil.com/photo.jpg")
      }.to raise_error(Persona::APIError, /untrusted host/)
    end

    it "rejects internal IPs" do
      expect {
        service.download_file("https://169.254.169.254/latest/meta-data/")
      }.to raise_error(Persona::APIError, /untrusted host/)
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
        },
        verifications: {
          data: [
            { type: "verification/government-id", id: "ver_gov123" }
          ]
        },
        sessions: { data: [] },
        documents: { data: [] },
        selfies: { data: [] }
      }
    }
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
        country_code: "US",
        front_photo: { filename: "front.jpg", url: "https://files.withpersona.com/front.jpg", byte_size: 12345 },
        back_photo: { filename: "back.jpg", url: "https://files.withpersona.com/back.jpg", byte_size: 12345 },
        selfie_photo: nil
      }
    }
  end
end
