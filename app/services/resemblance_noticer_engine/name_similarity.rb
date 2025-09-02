module ResemblanceNoticerEngine
  class NameSimilarity < Base
    def run
      # for now, just exact matches.
      # TODO: levenshtein or smth in the future?

      # Check all combinations of first_name/legal_first_name and last_name/legal_last_name
      query = Identity.none

      # Collect all possible first name and last name values from the identity (case insensitive)
      first_names = [ identity.first_name, identity.legal_first_name ].compact_blank.map(&:downcase).uniq
      last_names = [ identity.last_name, identity.legal_last_name ].compact_blank.map(&:downcase).uniq

      # i feel like this could be better...
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
