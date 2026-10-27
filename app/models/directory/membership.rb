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
                 (model.member_person&.full_name rescue nil) || "(deleted)"
               elsif model.member_group_id
                 (model.member_group&.name rescue nil) || "(deleted)"
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
    validate :no_cycles, if: -> { member_group_id.present? }
    validate :depth_within_limit, if: -> { member_group_id.present? }
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

    # Walk upward from collection_id through parent memberships.
    # If we reach member_group_id, adding this edge would create a cycle.
    def no_cycles
      return if collection_id.blank? || member_group_id.blank?

      cycle_found = self.class.connection.select_value(<<~SQL.squish)
        WITH RECURSIVE ancestors AS (
          SELECT #{self.class.connection.quote(collection_id)}::bigint AS id
          UNION
          SELECT m.collection_id
          FROM directory_memberships m
          INNER JOIN ancestors a ON a.id = m.member_group_id
          WHERE m.member_group_id IS NOT NULL
        )
        SELECT EXISTS (
          SELECT 1 FROM ancestors WHERE id = #{self.class.connection.quote(member_group_id)}
        )
      SQL

      errors.add(:base, "would create a cycle") if cycle_found
    end

    # Compute the longest path from any person up through this new edge to a root.
    # The depth is measured as the longest chain of group nesting from a leaf person to a root group.
    # We walk downward from member_group through all descendants, tracking depth,
    # then add the depth from collection upward to a root.
    def depth_within_limit
      return if collection_id.blank? || member_group_id.blank?

      max_depth = self.class.connection.select_value(<<~SQL)
        WITH RECURSIVE
        descendants AS (
          SELECT #{self.class.connection.quote(member_group_id)}::bigint AS id, 0 AS depth
          UNION ALL
          SELECT m.member_group_id, d.depth + 1
          FROM directory_memberships m
          INNER JOIN descendants d ON d.id = m.collection_id
          WHERE m.member_group_id IS NOT NULL
        ),
        ancestors AS (
          SELECT #{self.class.connection.quote(collection_id)}::bigint AS id, 1 AS depth
          UNION ALL
          SELECT m.collection_id, a.depth + 1
          FROM directory_memberships m
          INNER JOIN ancestors a ON a.id = m.member_group_id
          WHERE m.member_group_id IS NOT NULL
        )
        SELECT COALESCE(
          (SELECT MAX(d.depth) FROM descendants d) +
          (SELECT MAX(a.depth) FROM ancestors a),
          0
        )
      SQL

      if max_depth.to_i > Directory::MAX_DEPTH
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
    rescue => e
      Rails.logger.warn("[Directory] Activity tracking failed: #{e.message}")
    end

    def track_removal_on_person_and_collection
      return unless member_person_id
      expired = expires_at.present? && expires_at <= Time.current
      name = begin; member_person&.full_name; rescue; nil; end || "(deleted)"
      collection&.create_activity :member_removed,
        owner: nil,
        params: { member_name: name, reason: expired ? "expired" : "removed" }
    rescue => e
      Rails.logger.warn("[Directory] Activity tracking failed: #{e.message}")
    end
  end
end
