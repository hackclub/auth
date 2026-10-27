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
  end
end
