require "rails_helper"

# the whole thing, end to end.
#
# identity signs up → persona flag routes them → page renders →
# persona sends inquiry.completed webhook → job creates records →
# persona sends inquiry.approved webhook → identity is verified.
#
# also: the sad path (declined), resume flow, and idempotency.
RSpec.describe "Persona verification lifecycle", type: :request do
  let(:identity) { create(:identity, persona_account_id: nil, legal_first_name: nil, legal_last_name: nil, birthday: Date.parse("2008-06-15")) }
  let(:session) do
    identity.sessions.create!(
      session_token: SecureRandom.hex(32),
      expires_at: 1.week.from_now
    )
  end
  let(:webhook_secret) { "whsec_lifecycle_test" }
  let(:mock_credentials) do
    double(template_id: "itmpl_test_abc", api_key: "persona_sandbox_test", webhook_secret: webhook_secret)
  end

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_session).and_return(session)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
    Flipper.enable(:persona_verification_2026_04_09, identity)
    allow(Rails.application.credentials).to receive(:persona).and_return(mock_credentials)
  end

  after { Flipper.disable(:persona_verification_2026_04_09) }

  def sign_payload(body, timestamp: Time.now.to_i)
    sig = OpenSSL::HMAC.hexdigest("SHA256", webhook_secret, "#{timestamp}.#{body}")
    "t=#{timestamp},v1=#{sig}"
  end

  def send_webhook(event_name, inquiry_id)
    body = {
      data: {
        attributes: {
          name: event_name,
          payload: {
            data: {
              id: inquiry_id,
              type: "inquiry",
              attributes: { status: event_name.split(".").last }
            }
          }
        }
      }
    }.to_json

    post "/webhooks/persona",
      params: body,
      headers: {
        "Content-Type" => "application/json",
        "Persona-Signature" => sign_payload(body)
      }
  end

  describe "happy path: identity → persona page → completed → approved" do
    it "verifies an identity end to end" do
      # step 1: routing sends them to persona
      get "/verifications/new"
      expect(response).to redirect_to(persona_verification_path)

      # step 2: persona page renders, creates draft verification + inquiry
      get "/verifications/persona"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-inquiry-id")
      expect(response.body).to include("data-session-token")

      verification = identity.persona_verifications.draft.last
      expect(verification).to be_present
      inquiry_id = verification.persona_inquiry_id
      expect(inquiry_id).to start_with("inq_")
      expect(verification.persona_session_token).to be_present

      # persona_account_id is now set on the identity
      identity.reload
      expect(identity.persona_account_id).to start_with("act_")

      # step 3: persona sends inquiry.completed webhook
      send_webhook("inquiry.completed", inquiry_id)
      expect(response).to have_http_status(:ok)

      # process the enqueued job
      perform_enqueued_jobs(only: Persona::ProcessInquiryEventJob)

      verification.reload
      expect(verification).to be_pending
      expect(verification.persona_record).to be_present
      expect(verification.persona_record.name_first).to eq("HEIDI")
      expect(verification.persona_record.name_last).to eq("TRASHWORTH")
      expect(verification.persona_record.birthdate).to eq(Date.parse("2008-06-15"))
      expect(verification.persona_record.country_code).to eq("US")
      expect(verification.identity_document).to be_present
      expect(verification.identity_document.document_type).to eq("persona_gov_id")

      # step 4: persona sends inquiry.approved webhook
      # webhook handler enqueues ProcessInquiryEventJob, which enqueues VerificationPipelineJob
      persona_jobs = [Persona::ProcessInquiryEventJob, Persona::VerificationPipelineJob]
      send_webhook("inquiry.approved", inquiry_id)
      expect(response).to have_http_status(:ok)

      perform_enqueued_jobs(only: persona_jobs)
      perform_enqueued_jobs(only: persona_jobs)

      verification.reload
      expect(verification).to be_approved

      # ysws_eligible is set based on birthdate (2008 = ~17 in 2026)
      identity.reload
      expect(identity.ysws_eligible).to be true
      expect(identity.verification_status).to eq("verified")

      # approval mailer was enqueued
      expect(enqueued_jobs.select { |j| j["job_class"] == "ActionMailer::MailDeliveryJob" }).not_to be_empty

      # step 5: now /verifications/new redirects to status (already verified)
      get "/verifications/new"
      expect(response).to redirect_to(verification_status_path)
    end
  end

  describe "declined path: completed → declined" do
    it "rejects the identity and sends the right mailer" do
      # set up: get to persona page, create the verification
      get "/verifications/persona"
      verification = identity.persona_verifications.draft.last
      inquiry_id = verification.persona_inquiry_id

      # completed webhook
      send_webhook("inquiry.completed", inquiry_id)
      perform_enqueued_jobs(only: Persona::ProcessInquiryEventJob)

      verification.reload
      expect(verification).to be_pending

      # declined webhook
      send_webhook("inquiry.declined", inquiry_id)
      perform_enqueued_jobs(only: Persona::ProcessInquiryEventJob)

      verification.reload
      expect(verification).to be_rejected
      expect(verification.rejection_reason).to eq("other")
      expect(verification.fatal?).to be false

      identity.reload
      expect(identity.verification_status).to eq("needs_submission")
    end
  end

  describe "resume flow: user drops out and comes back" do
    it "reuses the existing inquiry instead of creating a new one" do
      # first visit — creates draft + inquiry
      get "/verifications/persona"
      verification = identity.persona_verifications.draft.last
      original_inquiry_id = verification.persona_inquiry_id
      original_token = verification.persona_session_token

      # second visit — should reuse the same verification, same inquiry, fresh token
      get "/verifications/persona"

      expect(identity.persona_verifications.draft.count).to eq(1)
      verification.reload
      expect(verification.persona_inquiry_id).to eq(original_inquiry_id)
      expect(verification.persona_session_token).not_to eq(original_token)
    end
  end

  describe "idempotency: duplicate webhooks" do
    it "handles double-delivered inquiry.completed gracefully" do
      get "/verifications/persona"
      verification = identity.persona_verifications.draft.last
      inquiry_id = verification.persona_inquiry_id

      # first delivery
      send_webhook("inquiry.completed", inquiry_id)
      perform_enqueued_jobs(only: Persona::ProcessInquiryEventJob)

      record_count = Identity::PersonaRecord.count
      doc_count = Identity::Document.count

      # second delivery — should be a no-op
      send_webhook("inquiry.completed", inquiry_id)
      perform_enqueued_jobs(only: Persona::ProcessInquiryEventJob)

      expect(Identity::PersonaRecord.count).to eq(record_count)
      expect(Identity::Document.count).to eq(doc_count)
    end

    it "handles double-delivered inquiry.approved gracefully" do
      get "/verifications/persona"
      verification = identity.persona_verifications.draft.last
      inquiry_id = verification.persona_inquiry_id

      send_webhook("inquiry.completed", inquiry_id)
      perform_enqueued_jobs(only: Persona::ProcessInquiryEventJob)

      persona_jobs = [Persona::ProcessInquiryEventJob, Persona::VerificationPipelineJob]

      send_webhook("inquiry.approved", inquiry_id)
      perform_enqueued_jobs(only: persona_jobs)
      perform_enqueued_jobs(only: persona_jobs)

      # second approval — should be a no-op, not raise
      send_webhook("inquiry.approved", inquiry_id)
      perform_enqueued_jobs(only: persona_jobs)
      perform_enqueued_jobs(only: persona_jobs)

      verification.reload
      expect(verification).to be_approved
    end
  end

  describe "status redirects" do
    it "redirects to status when verification is pending" do
      create(:persona_verification, :pending, identity: identity)

      get "/verifications/persona"
      expect(response).to redirect_to(verification_status_path)
    end

    it "redirects to status when verification is approved" do
      create(:persona_verification, :approved, identity: identity)

      get "/verifications/persona"
      expect(response).to redirect_to(verification_status_path)
    end

    it "redirects to status when identity is ineligible" do
      create(:persona_verification, :fatal_rejection, identity: identity)

      get "/verifications/persona"
      expect(response).to redirect_to(verification_status_path)
    end
  end

  describe "API failure graceful degradation" do
    it "shows fallback when Persona API is down" do
      mock_service = instance_double(Persona::MockAPIService)
      allow(Persona).to receive(:instance).and_return(mock_service)
      allow(mock_service).to receive(:create_inquiry).and_raise(Persona::APIError, "connection refused")

      get "/verifications/persona"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("verification provider")
      # should have a fallback link to document upload
      expect(response.body).to include("verifications")
    end
  end

  describe "webhook security" do
    it "rejects webhooks with wrong secret" do
      get "/verifications/persona"
      verification = identity.persona_verifications.draft.last

      body = {
        data: {
          attributes: {
            name: "inquiry.completed",
            payload: { data: { id: verification.persona_inquiry_id, type: "inquiry" } }
          }
        }
      }.to_json

      wrong_sig = OpenSSL::HMAC.hexdigest("SHA256", "wrong_secret", "#{Time.now.to_i}.#{body}")

      post "/webhooks/persona",
        params: body,
        headers: {
          "Content-Type" => "application/json",
          "Persona-Signature" => "t=#{Time.now.to_i},v1=#{wrong_sig}"
        }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects webhooks with replayed timestamp" do
      get "/verifications/persona"
      verification = identity.persona_verifications.draft.last

      body = {
        data: {
          attributes: {
            name: "inquiry.completed",
            payload: { data: { id: verification.persona_inquiry_id, type: "inquiry" } }
          }
        }
      }.to_json

      old_ts = 10.minutes.ago.to_i
      sig = OpenSSL::HMAC.hexdigest("SHA256", webhook_secret, "#{old_ts}.#{body}")

      post "/webhooks/persona",
        params: body,
        headers: {
          "Content-Type" => "application/json",
          "Persona-Signature" => "t=#{old_ts},v1=#{sig}"
        }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
