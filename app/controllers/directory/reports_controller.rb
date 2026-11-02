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

      @exposed_entitlements = Directory::Collection.entitlements
        .joins("INNER JOIN directory_exposures ON directory_exposures.entitlement_id = directory_collections.id")
        .group("directory_collections.id")
        .having("COUNT(directory_exposures.id) > 3")
        .select("directory_collections.*, COUNT(directory_exposures.id) AS exposure_count")
        .load_async

      @email_misses = PublicActivity::Activity
        .where(key: "directory_collection.email_lookup_miss")
        .where("created_at > ?", 1.day.ago)
        .group(:owner_id)
        .count
    end
  end
end
