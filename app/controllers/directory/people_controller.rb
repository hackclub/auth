# frozen_string_literal: true

module Directory
  class PeopleController < BaseController
    def index
      authorize Directory::Person, :create? # admin only
      add_breadcrumb t("directory.people.index.title")

      @people = Directory::Person.includes(:identity).order("identities.first_name").page(params[:page]).per(50)
      page_ids = @people.map(&:id)
      @holds_nothing_ids = Directory::Person
        .where(id: page_ids)
        .left_joins(:effective_memberships)
        .where(directory_effective_memberships: { person_id: nil })
        .pluck(:id)
        .to_set

      if params[:email].present?
        term = ActiveRecord::Base.sanitize_sql_like(params[:email].strip.downcase)
        @search_results = Identity.where("lower(primary_email) LIKE ?", "%#{term}%").limit(20)
      end
    end

    def show
      @person = Directory::Person.find(params[:id])
      authorize @person
      add_breadcrumb t("directory.people.index.title"), directory_people_path
      add_breadcrumb @person.full_name

      @visible_memberships = @person.memberships_with_via_path.select { |m| policy(m[:collection]).show? }

      @manageable_collections = Directory::Collection
        .joins("INNER JOIN directory_effective_grants ON directory_effective_grants.target_collection_id = directory_collections.id")
        .where(directory_effective_grants: { person_id: @person.id, permission: "manage_members" })
        .distinct
        .order(:name)

      @activities = PublicActivity::Activity
        .where(trackable: @person)
        .or(PublicActivity::Activity.where(owner: @person.identity))
        .order(created_at: :desc)
        .limit(20)
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

      # Capture revocation data BEFORE destroy wipes effective_memberships
      revocations = @person.revocation_data

      Directory.mutate!(cause: "person_removed:#{@person.id}") do
        @person.destroy!
      end

      # Enqueue revocations directly since the rebuild diff won't find them
      if revocations.any?
        Directory::AfterChangeJob.perform_later(change_ids: [], revocations: revocations)
      end

      redirect_to directory_people_path, notice: t("directory.people.destroyed")
    end

    private
  end
end
