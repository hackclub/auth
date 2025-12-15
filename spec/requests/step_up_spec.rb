require "rails_helper"

RSpec.describe "StepUp", type: :request do
  let(:identity) { create(:identity) }
  let(:session) do
    identity.sessions.create!(
      session_token: SecureRandom.hex(32),
      expires_at: 1.week.from_now
    )
  end

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_session).and_return(session)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  describe "email step-up method blocked for email_change action" do
    describe "POST /step_up/send_email_code" do
      it "rejects email code request for email_change action" do
        post "/step_up/send_email_code", params: { action_type: "email_change", return_to: "/email_changes/new" }

        expect(response).to redirect_to(new_step_up_path(action_type: "email_change", return_to: "/email_changes/new"))
        expect(flash[:error]).to eq("Email verification is not available for this action")
      end

      it "allows email code request for other actions" do
        post "/step_up/send_email_code", params: { action_type: "remove_totp", return_to: "/security" }

        expect(response).to redirect_to(new_step_up_path(action_type: "remove_totp", method: :email, return_to: "/security", code_sent: true))
        expect(flash[:notice]).to include("verification code has been sent")
      end
    end

    describe "POST /step_up/verify" do
      let!(:totp) do
        t = identity.totps.create!
        t.mark_verified!
        t
      end

      it "rejects email method verification for email_change action" do
        login_code = identity.v2_login_codes.create!

        post "/step_up/verify", params: {
          action_type: "email_change",
          method: "email",
          code: login_code.code,
          return_to: "/email_changes/new"
        }

        expect(response).to redirect_to(new_step_up_path(action_type: "email_change", return_to: "/email_changes/new"))
        expect(flash[:error]).to eq("Email verification is not available for this action")
      end

      it "allows TOTP verification for email_change action" do
        code = ROTP::TOTP.new(totp.secret).now

        post "/step_up/verify", params: {
          action_type: "email_change",
          method: "totp",
          code: code,
          return_to: "/email_changes/new"
        }

        expect(response).to redirect_to("/email_changes/new")
        expect(session.reload.last_step_up_at).to be_within(5.seconds).of(Time.current)
      end
    end

    describe "POST /step_up/resend_email" do
      it "rejects resend for email_change action" do
        post "/step_up/resend_email", params: { action_type: "email_change", return_to: "/email_changes/new" }

        expect(response).to redirect_to(new_step_up_path(action_type: "email_change", return_to: "/email_changes/new"))
        expect(flash[:error]).to eq("Email verification is not available for this action")
      end
    end
  end
end
