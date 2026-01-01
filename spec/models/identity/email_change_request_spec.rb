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
      request = build(:email_change_request, identity: identity, new_email: "test@mailinator.com")
      expect(request).not_to be_valid
      expect(request.errors[:new_email]).to include("cannot be a temporary email")
    end

    it "rejects email with invalid MX records" do
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
    let!(:pending_request) { create(:email_change_request, identity: identity, new_email: "pending@hackclub.com") }
    let!(:completed_request) { create(:email_change_request, identity: identity, new_email: "completed@hackclub.com", completed_at: Time.current) }
    let!(:cancelled_request) { create(:email_change_request, identity: identity, new_email: "cancelled@hackclub.com", cancelled_at: Time.current) }
    let!(:expired_request) { create(:email_change_request, identity: identity, new_email: "expired@hackclub.com", expires_at: 1.hour.ago) }

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
end
