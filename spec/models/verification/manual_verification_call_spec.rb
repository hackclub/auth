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
  describe "qa sampling" do
    # ids are assigned by the sequence, so build enough records that at
    # least one lands on a multiple of QA_SAMPLE_EVERY and pick by id
    def divisible?(v) = (v.id % described_class::QA_SAMPLE_EVERY).zero?

    it "queues only decided, unsampled decisions whose id is on the sampling step, oldest first" do
      decided = Array.new(described_class::QA_SAMPLE_EVERY * 2) { |i| create(:manual_verification_call, :approved, approved_at: i.days.ago) }
      pending = create(:manual_verification_call)
      sampled = create(:manual_verification_call, :sampled)

      queue = described_class.qa_candidates.to_a

      expect(queue).to all(satisfy { |v| divisible?(v) && v.decided? && !v.sampled? })
      expect(queue).to match_array(decided.select { |v| divisible?(v) })
      expect(queue).not_to include(pending, sampled)
      expect(queue.map(&:approved_at)).to eq(queue.map(&:approved_at).sort)
      expect(queue.first).to be_qa_candidate
      expect(pending).not_to be_qa_candidate
    end

    it "records a sample by a second reviewer" do
      verification = create(:manual_verification_call, :approved)
      other = create(:backend_user)

      verification.record_sample!(reviewer: other, verdict: "agree", notes: "  ")

      expect(verification.reload).to be_sampled
      expect(verification.sample_reviewer).to eq(other)
      expect(verification.sample_verdict).to eq("agree")
      expect(verification.sample_notes).to be_nil
      expect(described_class.qa_sampled).to include(verification)
    end

    it "refuses a reviewer sampling their own decision" do
      verification = create(:manual_verification_call, :approved)

      expect {
        verification.record_sample!(reviewer: verification.reviewer, verdict: "agree", notes: nil)
      }.to raise_error(ActiveRecord::RecordInvalid, /own decision/)
    end

    it "requires notes on a disagreement" do
      verification = create(:manual_verification_call, :rejected)

      expect {
        verification.record_sample!(reviewer: create(:backend_user), verdict: "disagree", notes: "")
      }.to raise_error(ActiveRecord::RecordInvalid, /notes/i)
    end

    it "refuses a second sample, even from a stale in-memory copy" do
      verification = create(:manual_verification_call, :approved)
      stale = described_class.find(verification.id)
      verification.record_sample!(reviewer: create(:backend_user), verdict: "agree", notes: nil)

      expect {
        stale.record_sample!(reviewer: create(:backend_user), verdict: "disagree", notes: "late to the party")
      }.to raise_error(described_class::AlreadySampled)
      expect(verification.reload.sample_verdict).to eq("agree")
    end

    it "rejects an unknown verdict" do
      verification = create(:manual_verification_call, :approved)

      expect {
        verification.record_sample!(reviewer: create(:backend_user), verdict: "maybe", notes: nil)
      }.to raise_error(ActiveRecord::RecordInvalid, /verdict/i)
    end
  end
end
