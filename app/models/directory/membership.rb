# frozen_string_literal: true

module Directory
  class Membership < ApplicationRecord
    has_paper_trail
    include PublicActivity::Model
    tracked owner: ->(controller, _model) { controller&.try(:user_for_public_activity) },
           recipient: ->(_, model) { model.collection },
           params: {
             collection_name: ->(_c, model) { model.collection&.name },
             member_name: ->(_c, model) {
               if model.member_person_id
                 model.member_person&.full_name || "(deleted)"
               elsif model.member_group_id
                 model.member_group&.name || "(deleted)"
               end
             },
             member_type: ->(_c, model) { model.member_person_id ? "person" : "group" },
             expires_at: ->(_c, model) { model.expires_at&.iso8601 }
           }

    after_create :track_on_person_and_collection
    after_destroy :track_removal_on_person_and_collection

    belongs_to :collection, class_name: "Directory::Collection"
    belongs_to :member_person, class_name: "Directory::Person", optional: true
    belongs_to :member_group, class_name: "Directory::Collection", optional: true
    belongs_to :created_by, class_name: "Identity", foreign_key: :created_by_identity_id, optional: true

    validate :exactly_one_member
    validate :member_group_must_be_group, if: -> { member_group_id.present? }
    validate :no_cycles_and_depth_within_limit, if: -> { member_group_id.present? }
    validate :expires_at_in_future, if: -> { expires_at.present? && expires_at_changed? }

    private

    def exactly_one_member
      has_person = member_person_id.present?
      has_group = member_group_id.present?

      if has_person == has_group
        errors.add(:base, "exactly one of member_person_id or member_group_id must be set")
      end
    end

    def member_group_must_be_group
      return unless member_group

      unless member_group.kind == "group"
        errors.add(:member_group, "must be a group")
      end
    end

    # Single CTE that walks ancestors (up from collection) and descendants (down from member_group)
    # to check for cycles and enforce MAX_DEPTH in one round trip.
    def no_cycles_and_depth_within_limit
      return if collection_id.blank? || member_group_id.blank?

      conn = self.class.connection
      quoted_collection = conn.quote(collection_id)
      quoted_member_group = conn.quote(member_group_id)
      max_depth = Directory::MAX_DEPTH

      result = conn.select_one(<<~SQL)
        WITH RECURSIVE
        ancestors AS (
          SELECT #{quoted_collection}::bigint AS id, 1 AS depth
          UNION ALL
          SELECT m.collection_id, a.depth + 1
          FROM directory_memberships m
          INNER JOIN ancestors a ON a.id = m.member_group_id
          WHERE m.member_group_id IS NOT NULL
            AND a.depth <= #{max_depth + 1}
        ),
        descendants AS (
          SELECT #{quoted_member_group}::bigint AS id, 0 AS depth
          UNION ALL
          SELECT m.member_group_id, d.depth + 1
          FROM directory_memberships m
          INNER JOIN descendants d ON d.id = m.collection_id
          WHERE m.member_group_id IS NOT NULL
            AND d.depth <= #{max_depth + 1}
        )
        SELECT
          EXISTS(SELECT 1 FROM ancestors WHERE id = #{quoted_member_group}) AS has_cycle,
          COALESCE((SELECT MAX(depth) FROM ancestors), 0) +
          COALESCE((SELECT MAX(depth) FROM descendants), 0) AS total_depth
      SQL

      if result["has_cycle"]
        errors.add(:base, "would create a cycle")
      elsif result["total_depth"].to_i > max_depth
        errors.add(:base, "would exceed maximum nesting depth of 6")
      end
    end

    def expires_at_in_future
      if expires_at <= Time.current
        errors.add(:expires_at, "must be in the future")
      end
    end

    def track_on_person_and_collection
      return unless member_person
      collection.create_activity :member_added,
        owner: created_by,
        recipient: member_person,
        params: { member_name: member_person.full_name, member_email: member_person.primary_email }
    rescue StandardError => e
      Rails.logger.error("[Directory] Activity tracking failed: #{e.message}")
      Sentry.capture_exception(e) if defined?(Sentry)
    end

    def track_removal_on_person_and_collection
      return unless member_person_id
      expired = expires_at.present? && expires_at <= Time.current
      name = begin; member_person&.full_name; rescue ActiveRecord::RecordNotFound; nil; end || "(deleted)"
      collection&.create_activity :member_removed,
        owner: nil,
        params: { member_name: name, reason: expired ? "expired" : "removed" }
    rescue StandardError => e
      Rails.logger.error("[Directory] Activity tracking failed: #{e.message}")
      Sentry.capture_exception(e) if defined?(Sentry)
    end
  end
end
