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
