# frozen_string_literal: true

module Directory
  class SearchController < BaseController
    def index
      authorize Directory::Collection.new, :index?
      add_breadcrumb t("directory.search.title")

      @query = params[:q].to_s.strip
      return if @query.blank?

      like = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"

      @collections = policy_scope(Directory::Collection)
        .where("name ILIKE :q OR slug ILIKE :q", q: like)
        .order(:name)
        .limit(50)

      @people = policy_scope(Directory::Person)
        .joins(:identity)
        .where(
          "identities.first_name ILIKE :q OR identities.last_name ILIKE :q OR identities.primary_email ILIKE :q",
          q: like
        )
        .includes(:identity)
        .order("identities.first_name")
        .limit(50)
    end

    def kbar
      authorize Directory::Collection.new, :index?
      query = params[:q].to_s.strip
      results = []
      return render(json: results) if query.length < 2

      if query.include?("!")
        prefix = query.split("!").first.downcase
        case prefix
        when "ident"
          identity = Identity.find_by_public_id(query)
          if identity
            person = Directory::Person.find_by(identity: identity)
            if person
              results << { type: "directory_person", id: person.public_id, label: person.full_name, sublabel: identity.primary_email, path: directory_person_path(person) }
            else
              results << { type: "identity", label: identity.full_name, sublabel: "#{identity.primary_email} (not in directory)", disabled: true }
            end
          end
        when "dper"
          person = Directory::Person.find_by_public_id(query)
          if person
            results << { type: "directory_person", id: person.public_id, label: person.full_name, sublabel: person.primary_email, path: directory_person_path(person) }
          end
        when "dcol"
          col = Directory::Collection.find_by_public_id(query)
          if col
            results << { type: "directory_collection", id: col.public_id, label: col.name, sublabel: "#{col.kind} · #{col.slug}", path: directory_collection_path(col.slug) }
          end
        end
        return render(json: results) if results.any? || query.split("!").last.length >= 3
      end

      like = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"

      policy_scope(Directory::Person).joins(:identity)
        .where("identities.first_name ILIKE :q OR identities.last_name ILIKE :q OR identities.primary_email ILIKE :q", q: like)
        .includes(:identity).limit(8).each do |person|
          results << { type: "directory_person", id: person.id, label: person.full_name, sublabel: person.primary_email, path: directory_person_path(person) }
        end

      policy_scope(Directory::Collection).where("name ILIKE :q OR slug ILIKE :q", q: like).limit(8).each do |col|
        results << { type: "directory_collection", id: col.id, label: col.name, sublabel: "#{col.kind} · #{col.slug}", path: directory_collection_path(col.slug) }
      end

      render json: results
    end
  end
end
