module ResemblanceNoticerEngine
  class DuplicateDocuments < Base
    def run
      # Build a map of checksum -> document for the current identity
      checksum_to_document = {}
      identity.documents.includes(files_attachments: :blob).each do |doc|
        doc.files.each do |file|
          checksum_to_document[file.blob.checksum] = doc
        end
      end

      return [] if checksum_to_document.empty?

      Identity::Document.joins(files_attachments: :blob)
        .joins(:identity)
        .where(active_storage_blobs: { checksum: checksum_to_document.keys })
        .where.not(identity: identity)
        .includes(:identity, files_attachments: :blob)
        .flat_map do |duplicate_doc|
        # Find which of our documents match this duplicate
        duplicate_doc.files.filter_map do |file|
          our_doc = checksum_to_document[file.blob.checksum]
          next unless our_doc

          Identity::Resemblance::ReusedDocumentResemblance.new(
            identity: identity,
            past_identity: duplicate_doc.identity,
            document: our_doc,
            past_document: duplicate_doc,
          )
        end
      end
    end
  end
end
