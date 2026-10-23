# frozen_string_literal: true

module Directory
  class PeopleController < BaseController
    def index
      authorize Directory::Person, :create? # admin only
      add_breadcrumb t("directory.people.index.title")

      @people = Directory::Person.includes(:identity).order("identities.first_name")
      @holds_nothing = Directory::Person
        .left_joins(:effective_memberships)
        .where(directory_effective_memberships: { person_id: nil })
    end

    def show
      @person = Directory::Person.find(params[:id])
      authorize @person
      add_breadcrumb t("directory.people.index.title"), directory_people_path
      add_breadcrumb @person.full_name

      @effective_memberships = @person.effective_memberships
        .includes(:collection)
        .order("directory_collections.name")

      direct_collection_ids = @person.memberships.pluck(:collection_id).to_set
      @grouped_memberships = @effective_memberships.group_by do |em|
        direct_collection_ids.include?(em.collection_id) ? :direct : :via
      end
    end

    def create
      authorize Directory::Person
      identity = Identity.find(params[:identity_id])

      person = Directory::Person.new(identity: identity, created_by_identity_id: current_identity.id)

      if person.save
        redirect_to directory_person_path(person), notice: t("directory.people.created")
      else
        redirect_to directory_people_path, alert: person.errors.full_messages.to_sentence
      end
    end

    def destroy
      @person = Directory::Person.find(params[:id])
      authorize @person

      ActiveRecord::Base.transaction do
        @person.destroy!
        Directory::Rebuild.call(cause: "person_deleted:#{@person.id}")
      end

      redirect_to directory_people_path, notice: t("directory.people.destroyed")
    end
  end
end
