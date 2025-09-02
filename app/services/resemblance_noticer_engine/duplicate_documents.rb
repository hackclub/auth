module ResemblanceNoticerEngine
  class DuplicateDocuments < Base
    def run
      checksums = identity.documents.joins(files_attachments: :blob).pluck("active_storage_blobs.checksum")
      return [] if checksums.empty?

      Identity::Document.joins(files_attachments: :blob)
        .joins(:identity)
        .where(active_storage_blobs: { checksum: checksums })
        .where.not(identity: identity)
        .includes(:identity, files_attachments: :blob)
        .map do |duplicate_doc|
        Identity::Resemblance::ReusedDocumentResemblance.new(
          identity: identity,
          past_identity: duplicate_doc.identity,
          document: duplicate_doc,
          past_document: duplicate_doc,
        )
      end
    end
  end
end
