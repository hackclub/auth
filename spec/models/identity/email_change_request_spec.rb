require "rails_helper"

RSpec.describe Identity::EmailChangeRequest do
  let(:identity) { create(:identity) }

  describe "validations" do
    it "requires new_email" do
      request = build(:email_change_request, identity: identity, new_email: nil)
      expect(request).not_to be_valid
      expect(request.errors[:new_email]).to include("can't be blank")
    end

    it "requires a valid email format" do
      request = build(:email_change_request, identity: identity, new_email: "not-an-email")
      expect(request).not_to be_valid
      expect(request.errors[:new_email]).to include("is invalid")
    end

    it "requires new_email to be different from old_email" do
      request = build(:email_change_request, identity: identity, new_email: identity.primary_email)
      expect(request).not_to be_valid
      expect(request.errors[:new_email]).to include("can't be your current email, ya goof!")
    end

    it "rejects email already taken by another identity" do
      other_identity = create(:identity, primary_email: "taken@hackclub.com")
      request = build(:email_change_request, identity: identity, new_email: "taken@hackclub.com")
      expect(request).not_to be_valid
      expect(request.errors[:new_email]).to include("is already taken by another account")
    end

    it "allows valid new email" do
      request = build(:email_change_request, identity: identity, new_email: "newemail@hackclub.com")
      expect(request).to be_valid
    end

    it "rejects disposable email addresses" do
      allow(Rails.env).to receive(:production?).and_return(true)

      request = build(:email_change_request, identity: identity, new_email: "test@mailinator.com")
      expect(request).not_to be_valid
      expect(request.errors[:new_email]).to include("cannot be a temporary email")
    end

    it "rejects email with invalid MX records" do
      allow(Rails.env).to receive(:production?).and_return(true)

      request = build(:email_change_request, identity: identity, new_email: "test@thisisnotarealdomain12345.com")
      expect(request).not_to be_valid
      expect(request.errors[:new_email]).to include("domain does not accept email")
    end
  end

  describe "defaults" do
    it "sets expires_at on create" do
      request = create(:email_change_request, identity: identity, new_email: "new@hackclub.com")
      expect(request.expires_at).to be_within(1.minute).of(24.hours.from_now)
    end

    it "sets old_email from identity on create" do
      request = create(:email_change_request, identity: identity, new_email: "new@hackclub.com")
      expect(request.old_email).to eq(identity.primary_email)
    end
  end

  describe "#pending?" do
    it "returns true for pending request" do
      request = create(:email_change_request, identity: identity, new_email: "new@hackclub.com")
      expect(request).to be_pending
    end

    it "returns false for completed request" do
      request = create(:email_change_request, identity: identity, new_email: "new@hackclub.com", completed_at: Time.current)
      expect(request).not_to be_pending
    end

    it "returns false for cancelled request" do
      request = create(:email_change_request, identity: identity, new_email: "new@hackclub.com", cancelled_at: Time.current)
      expect(request).not_to be_pending
    end

    it "returns false for expired request" do
      request = create(:email_change_request, identity: identity, new_email: "new@hackclub.com", expires_at: 1.hour.ago)
      expect(request).not_to be_pending
    end
  end

  describe "automatic token generation" do
    it "generates tokens on create" do
      request = create(:email_change_request, identity: identity, new_email: "new@hackclub.com")
      expect(request.old_email_token).to be_present
      expect(request.new_email_token).to be_present
      expect(request.old_email_token).not_to eq(request.new_email_token)
    end
  end

  describe "#verify_old_email!" do
    let(:request) { create(:email_change_request, identity: identity, new_email: "new@hackclub.com") }

    it "verifies old email with correct token" do
      expect(request.verify_old_email!(request.old_email_token)).to be true
      expect(request.reload.old_email_verified?).to be true
    end

    it "returns false for incorrect token" do
      expect(request.verify_old_email!("wrong-token")).to be false
      expect(request.old_email_verified?).to be false
    end

    it "returns false if request is not pending" do
      request.cancel!
      expect(request.verify_old_email!(request.old_email_token)).to be false
    end

    it "records verification IP address" do
      request.verify_old_email!(request.old_email_token, verified_from_ip: "192.168.1.100")
      expect(request.reload.old_email_verified_from_ip).to eq("192.168.1.100")
    end
  end

  describe "#verify_new_email!" do
    let(:request) { create(:email_change_request, identity: identity, new_email: "new@hackclub.com") }

    it "verifies new email with correct token" do
      expect(request.verify_new_email!(request.new_email_token)).to be true
      expect(request.reload.new_email_verified?).to be true
    end

    it "returns false for incorrect token" do
      expect(request.verify_new_email!("wrong-token")).to be false
      expect(request.new_email_verified?).to be false
    end

    it "returns false if request is not pending" do
      request.cancel!
      expect(request.verify_new_email!(request.new_email_token)).to be false
    end

    it "records verification IP address" do
      request.verify_new_email!(request.new_email_token, verified_from_ip: "10.0.0.50")
      expect(request.reload.new_email_verified_from_ip).to eq("10.0.0.50")
    end
  end

  describe "#complete_if_ready!" do
    let(:request) { create(:email_change_request, identity: identity, new_email: "new@hackclub.com") }

    it "completes when both emails are verified" do
      request.verify_old_email!(request.old_email_token)
      request.verify_new_email!(request.new_email_token)

      expect(request.reload).to be_completed
      expect(identity.reload.primary_email).to eq("new@hackclub.com")
    end

    it "does not complete with only old email verified" do
      original_email = request.old_email
      request.verify_old_email!(request.old_email_token)

      expect(request.reload).not_to be_completed
      expect(identity.reload.primary_email).to eq(original_email)
    end

    it "does not complete with only new email verified" do
      original_email = request.old_email
      request.verify_new_email!(request.new_email_token)

      expect(request.reload).not_to be_completed
      expect(identity.reload.primary_email).to eq(original_email)
    end

    it "sends notification email after completion" do
      expect {
        request.verify_old_email!(request.old_email_token)
        request.verify_new_email!(request.new_email_token)
      }.to have_enqueued_mail(EmailChangeMailer, :email_changed_notification)
    end

    it "creates an activity record" do
      original_email = request.old_email
      request.verify_old_email!(request.old_email_token)
      request.verify_new_email!(request.new_email_token)

      activity = identity.activities.last
      expect(activity.key).to eq("identity.email_changed")
      expect(activity.parameters[:old_email]).to eq(original_email)
      expect(activity.parameters[:new_email]).to eq("new@hackclub.com")
    end
    
    it "reprovisions Slack after completion" do
      expect(SCIMService).to recieve(:reprovision_identity_after_primary_email_change) do |identity:|
        expect(identity.primary_email). to eq("new@hackclub.com")
      end
      
      request.verify_old_email!(request.old_email_token)
      request.verify_new_email!(request.new_email_token)
    end

    it "still completes if Slack reprovisioning raises" do
      scenario = instance_double("OnboardingScenarios::Base")
      allow(request.identity).to recieve(:onboarding_scenario_instance).and_return(scenario)
      allow(SCIMService).to receive(:find_or_create_user).and_raise(StandardError, "Slack is down")

      original_slack_id = identity.slack_id

      request.verify_old_email!(request.old_email_token)
      request.verify_new_email!(request.new_email_token)

      expect(request.reload).to be_completed
      expect(identity.reload.primary_email).to eq("new@hackclub.com")
      expect(identity.reload.slack_id).to eq(original_slack_id)
    end 
  end

  describe "SCIMService.reprovision_identity_after_primary_email_change" do
    let(:scenario) { instance_double("OnboardingScenarios::Base") }
    let(:identity) {create(:identity, primary_email: "old@hackclub.com", slack_id: "UOLD12345") }

    before do
      allow(identity).to recieve(:onboarding_scenario_instance).and_return(scenario)
    end

    it "keeps existing Slack account when resolved Slack account is the same" do 
      allow(SCIMService).to recieve(:find_or_create_user).with(identity:, scenario:).and_return(
        success: true, slack_id: "UOLD12345", created: false
      )

      expect(identity).not_to recieve(:update!)
      expect {
        SCIMService.reprovision_identity_after_primary_email_change(idenity:)
      }.not_to change {identity.activities.count}
      expect(identity.reload.slack_id).to eq("UOLD12345")
    end

    it "updates to a different existing Slack account when found" do
      allow(SCIMService).to recieve(:find_or_create_user).with(identity:, scenario:).and_return(
        sucess: true, slack_id: "UEXISTING9", created: false
      )

      expect {
        SCIMService.reprovision_identity_after_primary_email_change(identity:)
      }.to change { indentity.reload.slack_id }.from("UOLD12345").to("UXISTING9")

      activity = identity.activities.find_by(key: "identity.slack_account_linked")
      expect(activity).to be_present
      expect(activity.parameters[:slack_id]).to eq("UEXISTING9")
    end

    it "updates to a new Slack account when created" do
      allow(SCIMService).to recieve(:find_or_create_user).with(identity:, scenario:).and_return(
        success: true, slack_id: "UNEW123456", created: true
      )

      expect {
        SCIMService.reprovision_identity_after_primary_email_change(identity:)
      }.to change { identity.reload.slack_id}.from("UOLD12345").to("UNEW123456")
      
      activity = identity.activate.find_by(key: "identity.slack_account_linked")
      expect(activity).to be_present
      expect(activity.parameters[:slack_id]).to eq("UNEW123456")
    end

    it "handles SCIM lookup/provisioning failure without raising" do
      allow(SCIMService).to receive(:find_or_create_user).with(identity:, scenario:).and_return(
        success: false, error: "lookup failed", created: false
      )

      expect { 
        SCIMService.reprovision_identity_after_primary_email_change(identity:)
      }.not_to raise_error
    end

    it "keeps existing Slack ID when reprovisioning fails" do
      allow(SKIMService).to recieve(:find_or_create_user).with(identity:,scenario:).and_return(
        success: false, error: "lookup faled", created: false
      )

      expect(identity).not_to receive(:update!)
      SCIMService.reprovision_identity_after_primary_email_change(identity:)
      expect(identity.reload.slack_id).to eq("UOLD12345")
    end
  end

  describe "#cancel!" do
    let(:request) { create(:email_change_request, identity: identity, new_email: "new@hackclub.com") }

    it "cancels a pending request" do
      expect(request.cancel!).to be true
      expect(request.reload).to be_cancelled
    end

    it "returns false for already completed request" do
      request.update!(completed_at: Time.current)
      expect(request.cancel!).to be false
    end

    it "creates a cancellation activity record" do
      request.cancel!
      activity = identity.activities.find_by(key: "identity.email_change_cancelled")
      expect(activity).to be_present
      expect(activity.parameters[:old_email]).to eq(request.old_email)
      expect(activity.parameters[:new_email]).to eq(request.new_email)
    end
  end

  describe "#complete_if_ready! race condition protection" do
    let(:request) { create(:email_change_request, identity: identity, new_email: "new@hackclub.com") }

    it "does not complete if request was cancelled" do
      request.verify_old_email!(request.old_email_token)
      request.update!(new_email_verified_at: Time.current)
      request.update!(cancelled_at: Time.current)

      original_email = identity.primary_email
      request.complete_if_ready!

      expect(request.reload).not_to be_completed
      expect(identity.reload.primary_email).to eq(original_email)
    end

    it "does not complete if request expired" do
      request.verify_old_email!(request.old_email_token)
      request.update!(new_email_verified_at: Time.current)
      request.update!(expires_at: 1.hour.ago)

      original_email = identity.primary_email
      request.complete_if_ready!

      expect(request.reload).not_to be_completed
      expect(identity.reload.primary_email).to eq(original_email)
    end
  end

  describe "scopes" do
    let(:identity2) { create(:identity) }
    let(:identity3) { create(:identity) }
    let(:identity4) { create(:identity) }
    let!(:pending_request) { create(:email_change_request, identity: identity, new_email: "pending@hackclub.com") }
    let!(:completed_request) { create(:email_change_request, identity: identity2, new_email: "completed@hackclub.com", completed_at: Time.current) }
    let!(:cancelled_request) { create(:email_change_request, identity: identity3, new_email: "cancelled@hackclub.com", cancelled_at: Time.current) }
    let!(:expired_request) { create(:email_change_request, identity: identity4, new_email: "expired@hackclub.com", expires_at: 1.hour.ago) }

    describe ".pending" do
      it "returns only pending requests" do
        expect(Identity::EmailChangeRequest.pending).to contain_exactly(pending_request)
      end
    end

    describe ".completed" do
      it "returns only completed requests" do
        expect(Identity::EmailChangeRequest.completed).to contain_exactly(completed_request)
      end
    end
  end

  describe "paper_trail" do
    it "tracks changes" do
      request = create(:email_change_request, identity: identity, new_email: "new@hackclub.com")
      expect(request.versions.count).to eq(1)

      request.update!(cancelled_at: Time.current)
      expect(request.versions.count).to eq(2)
    end
  end

  describe "email normalization" do
    it "normalizes new_email to lowercase and strips whitespace" do
      request = build(:email_change_request, identity: identity, new_email: "  NEW@HACKCLUB.COM  ")
      request.valid?
      expect(request.new_email).to eq("new@hackclub.com")
    end

    it "normalizes old_email to lowercase and strips whitespace" do
      request = build(:email_change_request, identity: identity, new_email: "new@hackclub.com", old_email: "  OLD@HACKCLUB.COM  ")
      request.valid?
      expect(request.old_email).to eq("old@hackclub.com")
    end
  end
end
