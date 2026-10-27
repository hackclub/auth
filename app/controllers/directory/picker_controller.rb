# frozen_string_literal: true

module Directory
  class PickerController < BaseController
    def search
      authorize Directory::Person, :picker?

      query = params[:q].to_s.strip
      scope = params[:scope].to_s.presence || "all"
      results = []

      if scope.in?(%w[people all])
        results.concat(search_people(query))
      end

      if scope.in?(%w[groups all])
        results.concat(search_collections(query, "group"))
      end

      if scope.in?(%w[entitlements all])
        results.concat(search_collections(query, "entitlement"))
      end

      render json: results
    end

    private

    def search_people(query)
      results = []

      # Exact email match — always works, even below 3 chars
      if query.include?("@")
        identity = Identity.find_by(primary_email: query)
        if identity
          person = Directory::Person.find_by(identity: identity)
          if person
            results << person_result(person)
          else
            results << {
              id: identity.id,
              label: identity.full_name,
              sublabel: identity.primary_email,
              type: "person",
              new_directory_person: true
            }
          end
        end
        return results
      end

      return results if query.length < 3

      people = policy_scope(Directory::Person)
        .joins(:identity)
        .where(
          "identities.first_name ILIKE :q OR identities.last_name ILIKE :q OR identities.primary_email ILIKE :q",
          q: "%#{sanitize_sql_like(query)}%"
        )
        .includes(:identity)
        .limit(20)

      people.each { |p| results << person_result(p) }
      results
    end

    def search_collections(query, kind)
      return [] if query.length < 3

      policy_scope(Directory::Collection)
        .where(kind: kind)
        .where("name ILIKE :q OR slug ILIKE :q", q: "%#{sanitize_sql_like(query)}%")
        .limit(20)
        .map do |c|
          {
            id: c.id,
            label: c.name,
            sublabel: c.slug,
            type: kind
          }
        end
    end

    def person_result(person)
      {
        id: person.id,
        label: person.full_name,
        sublabel: person.primary_email,
        type: "person"
      }
    end

    def sanitize_sql_like(string)
      ActiveRecord::Base.sanitize_sql_like(string)
    end
  end
end
