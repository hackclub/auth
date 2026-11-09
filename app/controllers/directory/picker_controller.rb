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

    # Exact-email lookups for a pasted batch, in one request. Same rules as an exact
    # email in #search.
    def resolve
      authorize Directory::Person, :picker?

      emails = Array(params[:emails]).map { |e| e.to_s.strip.downcase }.select { |e| e.include?("@") }.uniq
        .first(Directory::MembershipsController::MAX_BATCH_IDENTIFIERS)
      return render(json: []) if emails.empty?

      people = Directory::Person.joins(:identity).includes(:identity)
        .where("lower(identities.primary_email) IN (?)", emails)
      results = people.map { |p| person_result(p) }

      if policy(Directory::Person).create?
        missing = emails - results.map { |r| r[:sublabel].downcase }
        if missing.any?
          Identity.where("lower(primary_email) IN (?)", missing).where.not(id: people.map(&:identity_id)).find_each do |identity|
            results << { id: identity.public_id, label: identity.full_name, sublabel: identity.primary_email,
                         type: "person", new_directory_person: true }
          end
        end
      end

      render json: results
    end

    private

    # Partial search only covers people the viewer can already see; adding someone new
    # takes their exact email, which resolves regardless. ident! ids skip the picker.
    def search_people(query)
      return [] if query.start_with?("ident!")

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

      policy_scope(Directory::Person).search(query)
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
