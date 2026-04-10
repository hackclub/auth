require "rails_helper"

RSpec.describe "Webhooks::Persona", type: :request do
  let(:webhook_secret) { "whsec_test_secret_abc123" }
  let(:identity) { create(:identity) }
  let(:verification) { create(:persona_verification, identity: identity) }

  let(:inquiry_completed_payload) do
    {
      data: {
        attributes: {
          name: "inquiry.completed",
          payload: {
            data: {
              id: verification.persona_inquiry_id,
              type: "inquiry",
              attributes: {
                status: "completed",
                reference_id: identity.public_id
              }
            }
          }
        }
      }
    }.to_json
  end

  let(:inquiry_approved_payload) do
    {
      data: {
        attributes: {
          name: "inquiry.approved",
          payload: {
            data: {
              id: verification.persona_inquiry_id,
              type: "inquiry",
              attributes: {
                status: "approved",
                reference_id: identity.public_id
              }
            }
          }
        }
      }
    }.to_json
  end

  let(:inquiry_declined_payload) do
    {
      data: {
        attributes: {
          name: "inquiry.declined",
          payload: {
            data: {
              id: verification.persona_inquiry_id,
              type: "inquiry",
              attributes: {
                status: "declined",
                reference_id: identity.public_id
              }
            }
          }
        }
      }
    }.to_json
  end

  before do
    allow(Rails.application.credentials).to receive(:persona).and_return(
      OpenStruct.new(webhook_secret: webhook_secret)
    )
  end

  def sign_payload(body, secret: webhook_secret, timestamp: Time.now.to_i)
    signature = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
    "t=#{timestamp},v1=#{signature}"
  end

  describe "POST /webhooks/persona" do
    context "with valid signature" do
      it "returns 200" do
        post "/webhooks/persona",
          params: inquiry_completed_payload,
          headers: {
            "Content-Type" => "application/json",
            "Persona-Signature" => sign_payload(inquiry_completed_payload)
          }

        expect(response).to have_http_status(:ok)
      end

      it "enqueues ProcessInquiryEventJob for inquiry.completed" do
        expect {
          post "/webhooks/persona",
            params: inquiry_completed_payload,
            headers: {
              "Content-Type" => "application/json",
              "Persona-Signature" => sign_payload(inquiry_completed_payload)
            }
        }.to have_enqueued_job(Persona::ProcessInquiryEventJob)
      end

      it "enqueues job for inquiry.approved" do
        expect {
          post "/webhooks/persona",
            params: inquiry_approved_payload,
            headers: {
              "Content-Type" => "application/json",
              "Persona-Signature" => sign_payload(inquiry_approved_payload)
            }
        }.to have_enqueued_job(Persona::ProcessInquiryEventJob)
      end

      it "enqueues job for inquiry.declined" do
        expect {
          post "/webhooks/persona",
            params: inquiry_declined_payload,
            headers: {
              "Content-Type" => "application/json",
              "Persona-Signature" => sign_payload(inquiry_declined_payload)
            }
        }.to have_enqueued_job(Persona::ProcessInquiryEventJob)
      end
    end

    context "with invalid signature" do
      it "returns 401" do
        post "/webhooks/persona",
          params: inquiry_completed_payload,
          headers: {
            "Content-Type" => "application/json",
            "Persona-Signature" => "t=123,v1=badhexbadhexbadhex"
          }

        expect(response).to have_http_status(:unauthorized)
      end

      it "does not enqueue any jobs" do
        expect {
          post "/webhooks/persona",
            params: inquiry_completed_payload,
            headers: {
              "Content-Type" => "application/json",
              "Persona-Signature" => "t=123,v1=badhexbadhexbadhex"
            }
        }.not_to have_enqueued_job(Persona::ProcessInquiryEventJob)
      end
    end

    context "with missing signature" do
      it "returns 401" do
        post "/webhooks/persona",
          params: inquiry_completed_payload,
          headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with replayed timestamp (too old)" do
      it "returns 401 when timestamp is older than 5 minutes" do
        old_timestamp = 5.minutes.ago.to_i - 1
        signature = sign_payload(inquiry_completed_payload, timestamp: old_timestamp)

        post "/webhooks/persona",
          params: inquiry_completed_payload,
          headers: {
            "Content-Type" => "application/json",
            "Persona-Signature" => signature
          }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with malformed body" do
      it "returns 400" do
        body = "not json at all {"
        post "/webhooks/persona",
          params: body,
          headers: {
            "Content-Type" => "application/json",
            "Persona-Signature" => sign_payload(body)
          }

        expect(response).to have_http_status(:bad_request)
      end
    end

    context "with multiple signatures (key rotation)" do
      it "accepts if any v1 signature is valid" do
        valid_sig = sign_payload(inquiry_completed_payload)
        # extract t= and add an extra invalid v1 before the valid one
        parts = valid_sig.split(",")
        combined = "#{parts[0]},v1=oldinvalidsig,#{parts[1]}"

        post "/webhooks/persona",
          params: inquiry_completed_payload,
          headers: {
            "Content-Type" => "application/json",
            "Persona-Signature" => combined
          }

        expect(response).to have_http_status(:ok)
      end
    end
  end
end
