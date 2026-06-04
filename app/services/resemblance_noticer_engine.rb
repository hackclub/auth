module ResemblanceNoticerEngine
  TACTICS = [ NameSimilarity, DuplicateDocuments, EmailSubaddressing ]

  def self.run(identity, additional_names: [])
    TACTICS.each do |tactic|
      instance = tactic == NameSimilarity ? tactic.new(identity, additional_names:) : tactic.new(identity)
      instance.run.each do |resemblance|
        existing = identity.resemblances.find_by(
          type: resemblance.class.name,
          past_identity_id: resemblance.past_identity_id,
          document_id: resemblance.document_id,
          past_document_id: resemblance.past_document_id
        )
        resemblance.save! unless existing
      end
    end

    check_tombstone_collisions(identity, additional_names:)
  end

  def self.check_tombstone_collisions(identity, additional_names: [])
    names_and_dobs = []

    if identity.birthday.present?
      name = "#{identity.first_name} #{identity.last_name}"
      if identity.legal_first_name.present? || identity.legal_last_name.present?
        name = "#{name} #{identity.legal_first_name} #{identity.legal_last_name}"
      end
      names_and_dobs << [ name, identity.birthday ]
    end

    additional_names.each do |extra|
      next unless extra[:first].present? && extra[:last].present? && extra[:dob].present?
      names_and_dobs << [ "#{extra[:first]} #{extra[:last]}", extra[:dob] ]
    end

    names_and_dobs.each do |name, dob|
      DeletionService.check_for_name_combos(name, dob).each do |deletion|
        identity.tombstone_collisions.find_or_create_by!(deletion: deletion)
      end
    end
  end
end
