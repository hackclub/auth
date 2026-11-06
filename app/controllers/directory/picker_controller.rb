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

    # Intentionally unscoped — the directory only contains affiliated people,
    # and the picker needs to find them regardless of collection visibility.
    def search_people(query)
      # Public IDs bypass the picker — they're submitted directly via the form
      # to avoid exposing profile data for the 50k identities outside the directory.
      return [] if query.start_with?("ident!")

      # Exact email match — always works, even below 3 chars
      if query.include?("@")
        person = Directory::Person.joins(:identity).find_by("lower(identities.primary_email) = ?", query.downcase)
        return [ person_result(person) ] if person

        if policy(Directory::Person).create?
          identity = Identity.find_by("lower(primary_email) = ?", query.downcase)
          return identity ? [ identity_to_picker_result(identity) ] : []
        end

        return []
      end

      return [] if query.length < 3

      Directory::Person
        .joins(:identity)
        .where(
          "identities.first_name ILIKE :q OR identities.last_name ILIKE :q OR identities.primary_email ILIKE :q",
          q: "%#{sanitize_sql_like(query)}%"
        )
        .includes(:identity)
        .limit(20)
        .map { |p| person_result(p) }
    end

    def search_collections(query, kind)
      return [] if query.length < 3

      policy_scope(Directory::Collection)
        .where(kind: kind)
        .where("name ILIKE :q OR slug ILIKE :q", q: "%#{sanitize_sql_like(query)}%")
        .limit(20)
        .map do |c|
          {
            id: c.public_id,
            label: c.name,
            sublabel: c.slug,
            type: kind
          }
        end
    end

    def person_result(person)
      {
        id: person.public_id,
        label: person.full_name,
        sublabel: person.primary_email,
        type: "person"
      }
    end

    def identity_to_picker_result(identity)
      person = Directory::Person.find_by(identity: identity)
      if person
        person_result(person)
      else
        { id: identity.public_id, label: identity.full_name, sublabel: identity.primary_email,
          type: "person", new_directory_person: true }
      end
    end

    def sanitize_sql_like(string)
      ActiveRecord::Base.sanitize_sql_like(string)
    end
  end
end
