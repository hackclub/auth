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

  describe "POST /backend/verification_cases/:id/resend_link" do
    it "rotates the token, re-sends the invitation and logs it" do
      kase = create(:verification_case, :link_sent)
      old_token = kase.access_token

      expect {
        post resend_link_backend_verification_case_path(kase)
      }.to have_enqueued_mail(VerificationCaseMailer, :invitation)

      kase.reload
      expect(kase).to be_link_sent
      expect(kase.access_token).not_to eq(old_token)
      expect(kase.events.where(key: "link_resent").count).to eq(1)
      expect(response).to redirect_to(backend_verification_case_path(kase))
    end

    it "does not lock out a user who already opened their link" do
      kase = create(:verification_case, :link_sent, access_token_used_at: 1.hour.ago)

      post resend_link_backend_verification_case_path(kase)

      expect(kase.reload.access_token_used_at).to be_present
    end

    # a stale tab still showing the button after the user submitted docs
    it "refuses once the case is past the link, without touching the token" do
      kase = create(:verification_case, :docs_submitted, access_token_used_at: 1.hour.ago)
      old_token = kase.access_token
      used_at = kase.access_token_used_at

      expect {
        post resend_link_backend_verification_case_path(kase)
      }.not_to have_enqueued_mail(VerificationCaseMailer, :invitation)

      kase.reload
      expect(kase).to be_docs_submitted
      expect(kase.access_token).to eq(old_token)
      expect(kase.access_token_used_at).to be_within(1.second).of(used_at)
      expect(kase.events.where(key: "link_resent")).not_to exist
      expect(response).to redirect_to(backend_verification_case_path(kase))
      expect(flash[:warning]).to include("nothing to resend")
    end

    it "still refuses when the case moves on under a stale pre-check" do
      kase = create(:verification_case, :link_sent)
      old_token = kase.access_token
      allow_any_instance_of(VerificationCase).to receive(:may_send_link?).and_return(true)
      kase.update!(status: "docs_submitted", attested: true, biometric_consent: true)

      expect {
        post resend_link_backend_verification_case_path(kase)
      }.not_to have_enqueued_mail(VerificationCaseMailer, :invitation)

      kase.reload
      expect(kase).to be_docs_submitted
      expect(kase.access_token).to eq(old_token)
      expect(flash[:warning]).to include("isn't valid")
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
    # the shared Rejectable mail relays the internal reason to the user and
    # must never fire here. the staff-only slack ping is separate.
    def rejection_mail_jobs
      enqueued_jobs.select do |j|
        j[:args].first == "VerificationMailer" && j[:args].second.to_s.start_with?("rejected_")
      end
    end

    def guardian_pings = enqueued_jobs.select { |j| j[:job] == Slack::NotifyGuardiansJob }

    let(:full_checklist) do
      {
        doc_matches_live_face: "yes",
        doc_matches_selfie: "yes",
        name_dob_consistent: "yes",
        signals_clean: "yes",
        doc_unaltered: "yes"
      }
    end

    it "approves on the first reviewer's judgment, even with risk signals present" do
      kase = create(:verification_case, :call_held, persona_inquiry_id: "inq_test123",
        persona_signal_snapshot: { "network_signals" => { "country_code" => "RO" } })
      kase.identity.update_column(:created_at, 2.days.ago)

      patch decide_backend_verification_case_path(kase),
        params: { decision: "approve", checklist: full_checklist, confidence: "high" }

      kase.reload
      expect(kase).to be_approved
      expect(kase.verification).to be_approved
      expect(kase.verification.reviewer).to eq(verifier)
    end

    it "records the selfie item as n/a when the case has no selfie at all" do
      kase = create(:verification_case, :call_held) # persona-less direct upload, no selfie

      patch decide_backend_verification_case_path(kase),
        params: { decision: "approve", checklist: full_checklist.except(:doc_matches_selfie), confidence: "high" }

      kase.reload
      expect(kase).to be_approved
      expect(kase.verification.checklist).to have_key("doc_matches_selfie")
      expect(kase.verification.checklist_answer("doc_matches_selfie")).to be_nil
    end

    it "lets the reviewer answer the selfie item on a skip-persona case with a live selfie" do
      kase = create(:verification_case, :call_held, skip_persona: true)
      create(:verification_case_document, verification_case: kase, document_kind: "selfie")

      patch decide_backend_verification_case_path(kase),
        params: { decision: "approve", checklist: full_checklist, confidence: "high" }

      kase.reload
      expect(kase).to be_approved
      expect(kase.verification.checklist_answer("doc_matches_selfie")).to be(true)
    end

    it "denies with a rejection reason" do
      kase = create(:verification_case, :call_held, persona_inquiry_id: "inq_test456")

      patch decide_backend_verification_case_path(kase),
        params: { decision: "deny", checklist: full_checklist, confidence: "high", rejection_reason: "no_show" }

      kase.reload
      expect(kase).to be_denied
      expect(kase.verification).to be_rejected
    end

    it "emails the user on denial, without the internal reason" do
      kase = create(:verification_case, :call_held, persona_inquiry_id: "inq_test789")

      expect {
        patch decide_backend_verification_case_path(kase),
          params: { decision: "deny", checklist: full_checklist, confidence: "high",
                    rejection_reason: "fraud", rejection_reason_details: "internal note" }
      }.to have_enqueued_mail(VerificationCaseMailer, :denied).with(kase)
    end

    it "sends only the reason-free case email on a fatal denial" do
      kase = create(:verification_case, :call_held)

      expect {
        patch decide_backend_verification_case_path(kase),
          params: { decision: "deny", checklist: full_checklist, confidence: "high",
                    rejection_reason: "fraud", rejection_reason_details: "internal note" }
      }.to have_enqueued_mail(VerificationCaseMailer, :denied).with(kase)

      expect(rejection_mail_jobs).to be_empty
      expect(guardian_pings.size).to eq(1)

      verification = kase.reload.verification
      expect(verification).to be_rejected
      expect(verification.fatal).to be(true)
      expect(verification.rejection_reason).to eq("fraud")
      expect(verification.rejection_reason_details).to eq("internal note")
    end

    it "sends only the reason-free case email on a retryable denial" do
      kase = create(:verification_case, :call_held)

      expect {
        patch decide_backend_verification_case_path(kase),
          params: { decision: "deny", checklist: full_checklist, confidence: "high", rejection_reason: "no_show" }
      }.to have_enqueued_mail(VerificationCaseMailer, :denied).with(kase)

      expect(rejection_mail_jobs).to be_empty
      expect(guardian_pings).to be_empty
    end

    it "does not send the denial email on approval" do
      kase = create(:verification_case, :call_held)

      expect {
        patch decide_backend_verification_case_path(kase),
          params: { decision: "approve", checklist: full_checklist, confidence: "high" }
      }.to have_enqueued_mail(VerificationMailer, :approved)

      denial = enqueued_jobs.select { |j| j[:args].first(2) == [ "VerificationCaseMailer", "denied" ] }
      expect(denial).to be_empty
    end

    it "rejects deciding before the call is held" do
      kase = create(:verification_case, :call_scheduled)

      patch decide_backend_verification_case_path(kase),
        params: { decision: "approve", checklist: full_checklist, confidence: "high" }

      expect(kase.reload).to be_call_scheduled
      expect(kase.verification).to be_nil
    end
  end

  describe "PATCH /backend/verification_cases/:id/hold_call" do
    let(:kase) { create(:verification_case, :call_scheduled) }

    it "refuses without a screenshot and leaves the case scheduled" do
      patch hold_call_backend_verification_case_path(kase)

      expect(response).to redirect_to(backend_verification_case_path(kase))
      expect(flash[:error]).to include("screenshot is required")
      expect(kase.reload).to be_call_scheduled
      expect(kase.documents).to be_empty
    end

    it "stores the screenshot as staff evidence and marks the call held" do
      patch hold_call_backend_verification_case_path(kase), params: { screenshot: screenshot_upload("call.png") }

      expect(kase.reload).to be_call_held
      doc = kase.documents.sole
      expect(doc.document_kind).to eq("call_screenshot")
      expect(doc.source).to eq("staff_upload")
      expect(doc.file).to be_attached
      event = kase.events.find_by(key: "call_held")
      expect(event.data["screenshot_document_id"]).to eq(doc.id)
    end

    it "rejects a non-image screenshot without transitioning" do
      pdf = Rack::Test::UploadedFile.new(StringIO.new("fake pdf bytes"), "application/pdf", original_filename: "call.pdf")
      patch hold_call_backend_verification_case_path(kase), params: { screenshot: pdf }

      expect(flash[:error]).to include("Could not save")
      expect(kase.reload).to be_call_scheduled
      expect(kase.documents).to be_empty
    end
  end

  describe "POST /backend/verification_cases/:id/request_redo" do
    it "sends the case back behind the booking gate with a fresh link and the reviewer's message" do
      kase = create(:verification_case, :docs_submitted, persona_inquiry_id: "inq_blurry", access_token_used_at: 1.hour.ago)
      old_token = kase.access_token

      expect {
        post request_redo_backend_verification_case_path(kase), params: { message: "the photo is too blurry to read the name" }
      }.to have_enqueued_mail(VerificationCaseMailer, :redo_requested)

      kase.reload
      expect(kase).to be_link_sent
      expect(kase.access_token).not_to eq(old_token)
      expect(kase.access_token_used_at).to be_nil
      expect(kase.persona_inquiry_id).to be_nil

      event = kase.events.find_by(key: "redo_requested")
      expect(event.actor).to eq(verifier)
      expect(event.data).to include("message" => "the photo is too blurry to read the name", "previous_inquiry_id" => "inq_blurry")
    end

    it "requires a message" do
      kase = create(:verification_case, :docs_submitted)

      expect {
        post request_redo_backend_verification_case_path(kase), params: { message: "  " }
      }.not_to have_enqueued_mail(VerificationCaseMailer, :redo_requested)

      expect(kase.reload).to be_docs_submitted
    end

    it "refuses once a call is booked" do
      kase = create(:verification_case, :call_scheduled)

      expect {
        post request_redo_backend_verification_case_path(kase), params: { message: "redo please" }
      }.not_to have_enqueued_mail(VerificationCaseMailer, :redo_requested)

      expect(kase.reload).to be_call_scheduled
      expect(response).to redirect_to(backend_verification_case_path(kase))
    end
  end

  describe "POST /backend/verification_cases/:id/withdraw" do
    it "closes the case, revokes the flag, invalidates the link, and logs the reason" do
      kase = create(:verification_case, :call_scheduled)
      token = kase.access_token
      Flipper.enable(VerificationCase::FLIPPER_FLAG, kase.identity)

      post withdraw_backend_verification_case_path(kase), params: { reason: "opened on the wrong account" }

      kase.reload
      expect(kase).to be_withdrawn
      expect(kase.verification).to be_nil
      expect(kase.access_token).to be_nil
      expect(kase.consume_access_token!(token)).to be(false)
      expect(Flipper.enabled?(VerificationCase::FLIPPER_FLAG, kase.identity)).to be(false)

      event = kase.events.find_by(key: "case_withdrawn")
      expect(event.actor).to eq(verifier)
      expect(event.data).to eq("reason" => "opened on the wrong account")
    end

    it "lets a new case be opened for the identity afterwards" do
      kase = create(:verification_case, :link_sent)
      post withdraw_backend_verification_case_path(kase)
      expect(kase.reload).to be_withdrawn

      post backend_verification_cases_path, params: { identity_id: kase.identity.public_id }

      expect(kase.identity.verification_cases.open_cases.count).to eq(1)
      expect(kase.identity.verification_cases.count).to eq(2)
    end

    it "refuses on a decided case" do
      kase = create(:verification_case, :call_held)
      kase.approve!

      post withdraw_backend_verification_case_path(kase)

      expect(kase.reload).to be_approved
      expect(response).to redirect_to(backend_verification_case_path(kase))
    end

    it "lists withdrawn cases under recently closed, not open" do
      kase = create(:verification_case, :withdrawn)

      get backend_verification_cases_path

      expect(response.body).to include("0 open")
      expect(response.body).to include(kase.public_id)
      expect(response.body).to include("recently closed")
    end
  end

  describe "navigation" do
    it "links the cases queue from the backend home page" do
      get backend_root_path

      expect(response.body).to include(backend_verification_cases_path)
      expect(response.body).to include("Manual call cases")
    end

    it "exposes the cases queue in the kbar palette" do
      get backend_root_path

      kbar = JSON.parse(response.body[/id="kbar-data">(.*?)<\/script>/m, 1])
      entry = kbar["shortcuts"].find { |s| s["code"] == "CASE" }

      expect(entry).to be_present
      expect(entry["path"]).to eq(backend_verification_cases_path)
    end

    it "hides the cases queue from users who cannot review" do
      plain = create(:backend_user)

      codes = Shortcodes.all(plain).map(&:code)

      expect(codes).not_to include("CASE")
    end
  end
  describe "qa sampling" do
    def decided_case(reviewer: create(:backend_user), status: :approved)
      verification = create(:manual_verification_call, status, reviewer: reviewer)
      create(:verification_case, :call_held, identity: verification.identity, verification: verification,
        status: status == :approved ? :approved : :denied)
    end

    describe "GET /backend/verification_cases/qa" do
      it "lists candidates, skips the current reviewer's own decisions, and shows stats" do
        step = Verification::ManualVerificationCall::QA_SAMPLE_EVERY
        cases = Array.new(step * 2) { decided_case }
        own = Array.new(step) { decided_case(reviewer: verifier) }
        sampled = create(:manual_verification_call, :sampled)
        create(:verification_case, :call_held, identity: sampled.identity, verification: sampled, status: :approved)

        get qa_backend_verification_cases_path

        expect(response).to have_http_status(:ok)
        listed = cases.select { |k| (k.verification.id % step).zero? }
        expect(listed).not_to be_empty
        listed.each { |k| expect(response.body).to include(k.public_id) }
        own.each { |k| expect(response.body).not_to include(k.public_id) }
        expect(response.body).to include("#{cases.size + own.size + 1}</b> decided")
        expect(response.body).to include("1</b> sampled")
      end

      it "denies users without the verifier role" do
        pleb = create(:backend_user)
        allow_any_instance_of(Backend::ApplicationController).to receive(:current_identity).and_return(pleb.identity)

        get qa_backend_verification_cases_path

        expect(response).to redirect_to(backend_root_path)
      end
    end

    describe "POST /backend/verification_cases/:id/sample" do
      it "records an agreeing sample and logs it" do
        kase = decided_case

        post sample_backend_verification_case_path(kase), params: { verdict: "agree", notes: "" }

        expect(response).to redirect_to(backend_verification_case_path(kase))
        verification = kase.verification.reload
        expect(verification.sample_reviewer).to eq(verifier)
        expect(verification.sample_verdict).to eq("agree")
        event = kase.events.find_by(key: "qa_sampled")
        expect(event.actor).to eq(verifier)
        expect(event.data).to include("verdict" => "agree", "verification_id" => verification.id)
        expect(kase.comments).to be_empty
      end

      it "leaves a comment on a disagreement" do
        kase = decided_case(status: :rejected)

        post sample_backend_verification_case_path(kase), params: { verdict: "disagree", notes: "the selfie clearly matches the document" }

        expect(kase.verification.reload.sample_verdict).to eq("disagree")
        expect(kase.comments.sole.body).to include("qa sample: disagree")
        expect(kase.comments.sole.body).to include("selfie clearly matches")
      end

      it "refuses to sample twice" do
        kase = decided_case
        kase.verification.record_sample!(reviewer: create(:backend_user), verdict: "agree", notes: nil)

        post sample_backend_verification_case_path(kase), params: { verdict: "disagree", notes: "second opinion" }

        expect(flash[:warning]).to match(/already been sampled/)
        expect(kase.verification.reload.sample_verdict).to eq("agree")
        expect(kase.comments).to be_empty
      end

      it "refuses a reviewer sampling their own decision" do
        kase = decided_case(reviewer: verifier)

        post sample_backend_verification_case_path(kase), params: { verdict: "agree" }

        expect(flash[:error]).to match(/own decision/)
        expect(kase.verification.reload).not_to be_sampled
      end

      it "refuses an undecided case" do
        kase = create(:verification_case, :call_held)

        post sample_backend_verification_case_path(kase), params: { verdict: "agree" }

        expect(flash[:warning]).to match(/decided/)
      end
    end
  end

  def screenshot_upload(name)
    Rack::Test::UploadedFile.new(StringIO.new("fake png bytes"), "image/png", original_filename: name)
  end
end
