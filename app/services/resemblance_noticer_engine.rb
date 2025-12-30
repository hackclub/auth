module ResemblanceNoticerEngine
  TACTICS = [ NameSimilarity, DuplicateDocuments, EmailSubaddressing ]

  def self.run(identity)
    TACTICS.each do |tactic|
      tactic.new(identity).run.each do |resemblance|
        existing = identity.resemblances.find_by(
          type: resemblance.class.name,
          past_identity_id: resemblance.past_identity_id,
          document_id: resemblance.document_id,
          past_document_id: resemblance.past_document_id
        )
        resemblance.save! unless existing
      end
    end
  end
end
