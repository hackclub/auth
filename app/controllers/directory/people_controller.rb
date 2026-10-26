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

      if params[:email].present?
        @search_results = Identity.where("lower(primary_email) LIKE ?", "%#{params[:email].strip.downcase}%").limit(20)
      end
    end

    def show
      @person = Directory::Person.find(params[:id])
      authorize @person
      add_breadcrumb t("directory.people.index.title"), directory_people_path
      add_breadcrumb @person.full_name

      all_effective = @person.effective_memberships
        .includes(:collection)
        .order("directory_collections.name")

      direct_collection_ids = @person.memberships.pluck(:collection_id).to_set

      @visible_memberships = all_effective.filter_map do |em|
        next unless policy(em.collection).show?

        if direct_collection_ids.include?(em.collection_id)
          { collection: em.collection, direct: true, via_path: [] }
        else
          via = find_via_path(direct_collection_ids, em.collection_id)
          { collection: em.collection, direct: false, via_path: via }
        end
      end

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
      revocations = capture_revocations_for_person(@person)

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

    def find_via_path(direct_collection_ids, ancestor_id)
      link = Directory::Closure.where(ancestor_id: ancestor_id)
        .where(descendant_id: direct_collection_ids.to_a)
        .where.not(descendant_id: ancestor_id)
        .order(:depth)
        .first
      return [] unless link

      child = Directory::Collection.find_by(id: link.descendant_id)
      child ? [child] : []
    end

    def capture_revocations_for_person(person)
      entitlement_ids = person.effective_memberships
        .joins("INNER JOIN directory_collections ON directory_collections.id = directory_effective_memberships.collection_id")
        .where(directory_collections: { kind: "entitlement" })
        .pluck(:collection_id)

      return [] if entitlement_ids.empty?

      app_ids = (
        Directory::Exposure.where(entitlement_id: entitlement_ids).pluck(:app_id) +
        Directory::AppRequirement.where(entitlement_id: entitlement_ids).pluck(:app_id)
      ).uniq

      return [] if app_ids.empty?

      [{ identity_id: person.identity_id, email: person.primary_email, app_ids: app_ids }]
    end
  end
end
