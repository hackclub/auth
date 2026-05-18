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

    check_tombstone_collisions(identity)
  end

  def self.check_tombstone_collisions(identity)
    return unless identity.birthday.present?

    name = "#{identity.first_name} #{identity.last_name}"
    if identity.legal_first_name.present? || identity.legal_last_name.present?
      name = "#{name} #{identity.legal_first_name} #{identity.legal_last_name}"
    end

    matching_deletions = DeletionService.check_for_name_combos(name, identity.birthday)
    matching_deletions.each do |deletion|
      identity.tombstone_collisions.find_or_create_by!(deletion: deletion)
    end
  end
end
