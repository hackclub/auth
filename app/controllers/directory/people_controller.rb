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
        @existing_person_identity_ids = Directory::Person.where(identity_id: @search_results.select(:id)).pluck(:identity_id).to_set
      end
    end

    def show
      @person = Directory::Person.find_by_public_id!(params[:public_id])
      authorize @person
      add_breadcrumb t("directory.people.index.title"), directory_people_path
      add_breadcrumb @person.full_name

      # A via path names the person's direct group, which may be one the viewer can't see.
      # Keep the segments they can; the view says how many it left out.
      ctx = pundit_user
      @visible_memberships = @person.memberships_with_via_path.filter_map do |m|
        next unless policy(m[:collection]).show?

        via = m[:via_path].select { |c| ctx.can_any?(%w[view manage_members expose], c) }
        m.merge(via_path: via, hidden_via: m[:via_path].size - via.size)
      end

      @manageable_collections = Directory::Collection
        .joins("INNER JOIN directory_effective_grants ON directory_effective_grants.target_collection_id = directory_collections.id")
        .where(directory_effective_grants: { person_id: @person.id, permission: "manage_members" })
        .distinct
        .order(:name)
        .select { |c| policy(c).show? }

      @activities = directory_activities_for(@person)
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
    rescue ActiveRecord::RecordNotUnique
      existing = Directory::Person.find_by!(identity: identity)
      redirect_to directory_person_path(existing), notice: t("directory.people.created")
    end

    def destroy
      @person = Directory::Person.find_by_public_id!(params[:public_id])
      authorize @person

      # Capture revocation data BEFORE destroy wipes effective_memberships
      revocations = @person.revocation_data

      Directory.mutate!(cause: Directory.cause("person_removed", target: @person.id, actor: current_identity.id)) do
        @person.destroy!
      end

      # Enqueue revocations directly since the rebuild diff won't find them
      if revocations.any?
        Directory::AfterChangeJob.perform_later(change_ids: [], revocations: revocations)
      end

      redirect_to directory_people_path, notice: t("directory.people.destroyed")
    end

    private

    # Directory activity about this person: rows where they're the subject (trackable, or
    # recipient of "added to x") plus directory rows they wrote as a manager. Never the
    # identity's account-wide audit log (logins, legal name, email changes, oauth grants).
    # Non-admins only get rows that belong to a collection they can see.
    def directory_activities_for(person)
      activities = PublicActivity::Activity
      about_person = activities.where(trackable: person)
        .or(activities.where(recipient: person))
        .or(activities.where(owner: person.identity))

      scope = activities.where(trackable_type: Directory::ActivityController::TRACKABLE_TYPES).and(about_person)
      scope = scope.and(activities_in_visible_collections) unless directory_admin?
      scope.order(created_at: :desc).limit(20)
    end

    # Keeps directory activity that belongs to a collection the viewer can see, in SQL so the
    # 20-row window is filled with rows they may see. Membership rows name their collection as
    # the recipient, which outlives the membership. Grant and exposure rows are placed through
    # their live record, and person rows count when the viewer can see that person; once the
    # record is deleted there's nothing to place the row by, so it stays hidden.
    def activities_in_visible_collections
      activities = PublicActivity::Activity
      visible = policy_scope(Directory::Collection).select(:id)

      activities.where(trackable_type: "Directory::Collection", trackable_id: visible)
        .or(activities.where(trackable_type: "Directory::Membership", recipient_type: "Directory::Collection", recipient_id: visible))
        .or(activities.where(trackable_type: "Directory::Grant", trackable_id: Directory::Grant.where(target_collection_id: visible).select(:id)))
        .or(activities.where(trackable_type: "Directory::Exposure", trackable_id: Directory::Exposure.where(entitlement_id: visible).select(:id)))
        .or(activities.where(trackable_type: "Directory::Person", trackable_id: policy_scope(Directory::Person).select(:id)))
    end
  end
end
