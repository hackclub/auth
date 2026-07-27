require "rails_helper"

RSpec.describe "Cal.com webhooks", type: :request do
  let(:secret) { "test-calcom-secret" }
  let(:kase) { create(:verification_case, :docs_submitted) }

  let(:payload) do
    {
      triggerEvent: "BOOKING_CREATED",
      payload: {
        uid: "bkng_123",
        startTime: 2.days.from_now.iso8601,
        attendees: [ { email: kase.identity.primary_email } ],
        metadata: { casePublicId: kase.public_id }
      }
    }.to_json
  end

  def signature_for(body)
    OpenSSL::HMAC.hexdigest("SHA256", secret, body)
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("CALCOM_WEBHOOK_SECRET").and_return(secret)
  end

  it "rejects a missing signature" do
    post "/webhooks/calcom", params: payload, headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a bad signature" do
    post "/webhooks/calcom", params: payload,
      headers: { "CONTENT_TYPE" => "application/json", "X-Cal-Signature-256" => "bogus" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "enqueues booking processing for a valid signature" do
    expect {
      post "/webhooks/calcom", params: payload,
        headers: { "CONTENT_TYPE" => "application/json", "X-Cal-Signature-256" => signature_for(payload) }
    }.to have_enqueued_job(Calcom::ProcessBookingEventJob)
    expect(response).to have_http_status(:ok)
  end

  it "schedules the call when the job runs" do
    Calcom::ProcessBookingEventJob.perform_now(
      event: "BOOKING_CREATED",
      case_id: kase.id,
      booking_uid: "bkng_123",
      starts_at: 2.days.from_now.iso8601
    )
    expect(kase.reload).to be_call_scheduled
    expect(kase.booking_uid).to eq("bkng_123")
    expect(kase.events.where(key: "call_booked")).to exist
  end

  it "returns a cancelled booking to docs_submitted and emails a rebook nudge" do
    kase = create(:verification_case, :call_scheduled)

    expect {
      Calcom::ProcessBookingEventJob.perform_now(
        event: "BOOKING_CANCELLED",
        case_id: kase.id,
        booking_uid: kase.booking_uid,
        starts_at: nil
      )
    }.to have_enqueued_mail(VerificationCaseMailer, :call_cancelled)

    expect(kase.reload).to be_docs_submitted
    expect(kase.booking_uid).to be_nil
    expect(kase.call_starts_at).to be_nil
    expect(kase.events.where(key: "call_cancelled")).to exist
  end

  it "lets the user book again after a cancellation" do
    kase = create(:verification_case, :call_scheduled)
    Calcom::ProcessBookingEventJob.perform_now(event: "BOOKING_CANCELLED", case_id: kase.id, booking_uid: kase.booking_uid, starts_at: nil)
    Calcom::ProcessBookingEventJob.perform_now(event: "BOOKING_CREATED", case_id: kase.id, booking_uid: "bkng_rebooked", starts_at: 3.days.from_now.iso8601)

    expect(kase.reload).to be_call_scheduled
    expect(kase.booking_uid).to eq("bkng_rebooked")
  end
end
