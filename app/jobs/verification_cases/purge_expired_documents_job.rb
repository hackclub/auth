# nightly retention sweep: raw case documents and call recordings whose
# retention_delete_at has passed get their blobs purged. the rows stay
# as tombstones; the decision record and checklist live forever.
class VerificationCases::PurgeExpiredDocumentsJob < ApplicationJob
  queue_as :default

  def perform
    VerificationCase::Document.purgeable.find_each do |document|
      document.purge_file!
    rescue => e
      Sentry.capture_exception(e, tags: { component: "verification_cases" },
        extra: { document_id: document.id })
    end
  end
end
