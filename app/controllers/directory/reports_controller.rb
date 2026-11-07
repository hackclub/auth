# frozen_string_literal: true

module Directory
  class ReportsController < BaseController
    def index
      authorize :directory, :admin?
      add_breadcrumb t("directory.reports.title")

      @empty_collections = Directory::Collection
        .where.not(
          id: Directory::Membership.active.select(:collection_id)
        )
        .order(:name)
        .load_async

      @unmanaged_collections = Directory::Collection
        .where.not(
          id: Directory::Grant.where(permission: "manage_members").select(:target_collection_id)
        )
        .order(:name)
        .load_async

      @orphan_people = Directory::Person
        .left_joins(:effective_memberships)
        .where(directory_effective_memberships: { person_id: nil })
        .includes(:identity)
        .order("identities.first_name")
        .load_async

      @locked_people = Directory::Person.locked.includes(:identity).order("identities.first_name").load_async

      @old_memberships = Directory::Membership
        .where.not(member_person_id: nil)
        .where("directory_memberships.created_at < ?", 1.year.ago)
        .includes(:collection, member_person: :identity)
        .order(:created_at)
        .load_async

      @expiring_memberships = Directory::Membership
        .where.not(member_person_id: nil)
        .where(expires_at: ..30.days.from_now)
        .where("expires_at > ?", Time.current)
        .includes(:collection, member_person: :identity)
        .order(:expires_at)
        .load_async
    end
  end
end
