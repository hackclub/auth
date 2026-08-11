module ResemblanceNoticerEngine
  class NameSimilarity < Base
    def initialize(identity, additional_names: [])
      super(identity)
      @additional_names = additional_names
    end

    def run
      first_names = [ identity.first_name, identity.legal_first_name ].compact_blank.map(&:downcase)
      last_names = [ identity.last_name, identity.legal_last_name ].compact_blank.map(&:downcase)

      @additional_names.each do |extra|
        first_names << extra[:first].downcase if extra[:first].present?
        last_names << extra[:last].downcase if extra[:last].present?
      end

      first_names.uniq!
      last_names.uniq!

      query = Identity.none

      first_names.each do |fname|
        last_names.each do |lname|
          query = query.or(
            Identity.where("LOWER(first_name) = ? AND LOWER(last_name) = ?", fname, lname)
              .or(Identity.where("LOWER(legal_first_name) = ? AND LOWER(legal_last_name) = ?", fname, lname))
              .or(Identity.where("LOWER(first_name) = ? AND LOWER(legal_last_name) = ?", fname, lname))
              .or(Identity.where("LOWER(legal_first_name) = ? AND LOWER(last_name) = ?", fname, lname))
          )
        end
      end

      query.where.not(id: identity.id).map do |similar_identity|
        Identity::Resemblance::NameResemblance.new(
          identity: identity,
          past_identity: similar_identity,
        )
      end
    end
  end
end
