module ResemblanceNoticerEngine
  class EmailSubaddressing < Base
    def run
      return [] if identity.primary_email.blank?

      base_email = extract_base_email(identity.primary_email)

      # i'm still not convinced i understand why this SQL works...
      # theoretically it turns nora+1@hackclub.com and n.o.ra@hackclub.com into nora@hackclub.com?
      normalized_email_sql = <<~SQL.squish
        CONCAT(
          REPLACE(SPLIT_PART(SPLIT_PART(primary_email, '@', 1), '+', 1), '.', ''),
          '@',
          SPLIT_PART(primary_email, '@', 2)
        )
      SQL

      similar_identities = Identity.where.not(id: identity.id)
        .where("#{normalized_email_sql} = ?", base_email)
        .where.not(primary_email: identity.primary_email) # not this one lol!

      similar_identities.map do |similar_identity|
        other_base_email = extract_base_email(similar_identity.primary_email)
        next unless other_base_email == base_email

        Identity::Resemblance::EmailSubaddressResemblance.new(
          identity: identity,
          past_identity: similar_identity,
        )
      end.compact
    end

    private

    def extract_base_email(email)
      local_part, domain = email.split("@", 2)

      base_local_part = local_part.split("+").first
      base_local_part = base_local_part.gsub(".", "")

      "#{base_local_part}@#{domain}"
    end
  end
end
