# frozen_string_literal: true

require "rails_helper"

# Hackatime has adult users with no Slack account who need an identity to keep signing in
# to it. They sign up from its OAuth flow, which picks the scenario set on its program.
RSpec.describe "Signing up from Hackatime", type: :request do
  let(:slug) { OnboardingScenarios::Hackatime.slug }

  describe "an adult whose email has no Slack account" do
    before { allow(SlackService).to receive(:find_by_email).and_return(nil) }

    def sign_up_from(program)
      post signup_path, params: {
        return_to: "/oauth/authorize?client_id=#{program.uid}&response_type=code",
        identity: {
          first_name: "Orpheus",
          last_name: "Dino",
          primary_email: "orpheus@example.com",
          birthday: 30.years.ago.to_date.iso8601,
          country: "US"
        }
      }
    end

    it "gets an identity" do
      expect { sign_up_from(create(:program, onboarding_scenario: slug)) }.to change(Identity, :count).by(1)

      expect(Identity.find_by!(primary_email: "orpheus@example.com").onboarding_scenario).to eq(slug)
    end

    it "is still turned away from a program on another scenario" do
      expect { sign_up_from(create(:program)) }.not_to change(Identity, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "the first login" do
    let(:nineteenth_birthday) { 19.years.ago.to_date }

    before do
      allow(SCIMService).to receive(:find_or_create_user).and_return({ success: true, slack_id: "U0HACKATIME", created: false })
    end

    def log_in(identity)
      attempt = LoginAttempt.create!(identity:, authentication_factors: {}, provenance: "signup", next_action: "home")
      code = Identity::V2LoginCode.generate(identity)
      post verify_login_attempt_path(id: attempt.to_param), params: { code: code.code }
    end

    it "gives someone under 19 a Slack account" do
      identity = create(:identity, onboarding_scenario: slug, slack_id: nil, birthday: nineteenth_birthday + 1.day)

      log_in(identity)

      expect(identity.reload.slack_id).to eq("U0HACKATIME")
    end

    it "gives an adult no Slack account" do
      identity = create(:identity, onboarding_scenario: slug, slack_id: nil, birthday: nineteenth_birthday)

      log_in(identity)

      expect(SCIMService).not_to have_received(:find_or_create_user)
      expect(identity.reload.slack_id).to be_nil
    end
  end
end
