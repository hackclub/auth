require "rails_helper"

RSpec.describe VerificationCases::PurgeExpiredDocumentsJob, type: :job do
  it "purges blobs past retention and leaves tombstones" do
    due = create(:verification_case_document, :expired_retention)
    not_due = create(:verification_case_document, retention_delete_at: 1.month.from_now)
    undecided = create(:verification_case_document, retention_delete_at: nil)

    described_class.perform_now

    expect(due.reload.purged?).to be(true)
    expect(due.file.attached?).to be(false)
    expect(due.verification_case.events.where(key: "document_purged")).to exist

    expect(not_due.reload.purged?).to be(false)
    expect(undecided.reload.purged?).to be(false)
  end
end
