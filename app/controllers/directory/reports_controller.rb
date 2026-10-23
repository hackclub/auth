# frozen_string_literal: true

module Directory
  class ReportsController < BaseController
    def index
      authorize :directory, :admin?
      add_breadcrumb t("directory.reports.title")

      @empty_collections = Directory::Collection
        .left_joins(:memberships)
        .where(directory_memberships: { id: nil })
        .order(:name)

      @no_grant_collections = Directory::Collection
        .where.not(
          id: Directory::Grant.where(permission: "manage_members").select(:target_collection_id)
        )
        .order(:name)

      @holds_nothing_people = Directory::Person
        .left_joins(:effective_memberships)
        .where(directory_effective_memberships: { person_id: nil })
        .includes(:identity)
        .order("identities.first_name")

      @locked_people = Directory::Person.locked.includes(:identity).order("identities.first_name")

      @old_memberships = Directory::Membership
        .where("directory_memberships.created_at < ?", 1.year.ago)
        .includes(:collection, member_person: :identity)
        .order(:created_at)

      @expiring_memberships = Directory::Membership
        .where(expires_at: ..30.days.from_now)
        .where("expires_at > ?", Time.current)
        .includes(:collection, member_person: :identity)
        .order(:expires_at)
    end
  end
end
