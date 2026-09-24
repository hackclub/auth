require "rails_helper"

RSpec.describe Verification::ManualVerificationCall, type: :model do
  it "requires a reviewer" do
    verification = build(:manual_verification_call, reviewer: nil)
    expect(verification).not_to be_valid
  end

  it "requires a complete checklist to approve" do
    verification = create(:manual_verification_call)
    verification.checklist = { "confidence" => "high" }
    expect { verification.approve! }.to raise_error(ActiveRecord::RecordInvalid, /missing answers/)
  end

  it "approves with a full checklist" do
    verification = create(:manual_verification_call)
    verification.approve!
    expect(verification.reload).to be_approved
  end

  it "requires a confidence level" do
    verification = create(:manual_verification_call)
    verification.checklist = verification.checklist.except("confidence")
    expect { verification.approve! }.to raise_error(ActiveRecord::RecordInvalid, /confidence/)
  end

  it "records rejection with the shared machinery" do
    verification = create(:manual_verification_call)
    verification.mark_as_rejected!("no_show", nil)
    expect(verification.reload).to be_rejected
    expect(verification.fatal).to be(false)
  end

  it "treats fraud as fatal" do
    verification = create(:manual_verification_call)
    verification.mark_as_rejected!("fraud", nil)
    expect(verification.fatal).to be(true)
  end

  describe "#expired?" do
    it "is false with no expiry (tier A)" do
      expect(build(:manual_verification_call, expires_at: nil).expired?).to be(false)
    end

    it "is true past expiry (tier B backstop)" do
      expect(build(:manual_verification_call, expires_at: 1.day.ago).expired?).to be(true)
    end
  end
end
