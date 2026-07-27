require "rails_helper"

RSpec.describe "Backend verification cases", type: :request do
  let(:verifier) { create(:backend_user, manual_document_verifier: true) }

  before do
    allow_any_instance_of(Backend::ApplicationController).to receive(:current_identity).and_return(verifier.identity)
    allow_any_instance_of(Backend::ApplicationController).to receive(:authenticate_user!).and_return(true)
    allow_any_instance_of(Backend::ApplicationController).to receive(:require_2fa!).and_return(true)
  end

  after { Flipper.disable(VerificationCase::FLIPPER_FLAG) }

  describe "POST /backend/verification_cases" do
    it "opens a case, enables the flag, and emails the single-use link" do
      target = create(:identity)

      expect {
        post backend_verification_cases_path, params: { identity_id: target.public_id }
      }.to have_enqueued_mail(VerificationCaseMailer, :invitation)

      kase = target.verification_cases.sole
      expect(kase).to be_link_sent
      expect(kase.skip_persona).to be(false)
      expect(Flipper.enabled?(VerificationCase::FLIPPER_FLAG, target)).to be(true)
    end

    it "opens a skip-persona case when asked" do
      target = create(:identity)
      post backend_verification_cases_path, params: { identity_id: target.public_id, skip_persona: "1" }
      expect(target.verification_cases.sole.skip_persona).to be(true)
    end
  end

  describe "POST /backend/verification_cases/:id/comment" do
    it "records a comment by the current reviewer" do
      kase = create(:verification_case, :docs_submitted)

      post comment_backend_verification_case_path(kase), params: { body: "docs look consistent with the account" }

      comment = kase.comments.sole
      expect(comment.author).to eq(verifier)
      expect(comment.body).to include("consistent")
    end
  end

  describe "PATCH /backend/verification_cases/:id/decide" do
    let(:full_checklist) do
      {
        doc_matches_live_face: "yes",
        doc_matches_persona_selfie: "yes",
        name_dob_consistent: "yes",
        signals_clean: "yes",
        doc_unaltered: "yes"
      }
    end

    it "approves on the first reviewer's judgment, even with risk signals present" do
      kase = create(:verification_case, :call_held, persona_inquiry_id: "inq_test123",
        persona_signal_snapshot: { "network_signals" => { "country_code" => "RO" } })
      kase.identity.update_column(:created_at, 2.days.ago) # would have auto-escalated before

      patch decide_backend_verification_case_path(kase),
        params: { decision: "approve", checklist: full_checklist, confidence: "high" }

      kase.reload
      expect(kase).to be_approved
      expect(kase.verification).to be_approved
      expect(kase.verification.reviewer).to eq(verifier)
    end

    it "decides a no-persona case with the selfie item recorded as n/a" do
      kase = create(:verification_case, :call_held, skip_persona: true)

      patch decide_backend_verification_case_path(kase),
        params: { decision: "approve", checklist: full_checklist.except(:doc_matches_persona_selfie), confidence: "high" }

      kase.reload
      expect(kase).to be_approved
      expect(kase.verification.checklist).to have_key("doc_matches_persona_selfie")
      expect(kase.verification.checklist_answer("doc_matches_persona_selfie")).to be_nil
    end

    it "denies with a rejection reason" do
      kase = create(:verification_case, :call_held, persona_inquiry_id: "inq_test456")

      patch decide_backend_verification_case_path(kase),
        params: { decision: "deny", checklist: full_checklist, confidence: "high", rejection_reason: "no_show" }

      kase.reload
      expect(kase).to be_denied
      expect(kase.verification).to be_rejected
    end

    it "blocks the escalating reviewer from resolving their own escalation" do
      kase = create(:verification_case, :escalated)
      kase.log_event!(:escalated, actor: verifier)

      patch decide_backend_verification_case_path(kase),
        params: { decision: "approve", checklist: full_checklist, confidence: "high" }

      expect(kase.reload).to be_escalated
      expect(kase.verification).to be_nil
    end
  end
end
