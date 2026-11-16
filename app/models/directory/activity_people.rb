# frozen_string_literal: true

module Directory
  # directory activity rows point at people by identity id and look the name up when shown,
  # so nothing about a person sits in the audit log after they're deleted
  module ActivityPeople
    DELETED = "[deleted user]"

    module_function

    # identities: { id => Identity } preloaded with_deleted, or nil to look it up
    def name(identity_id, identities = nil)
      identity = find(identity_id, identities)
      return DELETED unless identity

      identity.full_name
    end

    def email(identity_id, identities = nil)
      find(identity_id, identities)&.primary_email
    end

    def find(identity_id, identities = nil)
      return if identity_id.blank?

      identity = identities ? identities[identity_id.to_i] : Identity.with_deleted.find_by(id: identity_id)
      identity unless identity.nil? || identity.deleted_at.present?
    end

    # the member a membership row is about, without any visibility checks (the directory's
    # own activity_member_name adds those for groups)
    def member_name(activity, identities = nil)
      params = activity.parameters
      return params["member_name"] if params["member_type"] == "group"
      return name(params["member_identity_id"], identities) if params.key?("member_identity_id")

      params["member_name"]
    end

    def identity_ids(activities)
      activities.flat_map { |a| a.parameters.values_at("identity_id", "member_identity_id") }.compact.map(&:to_i).uniq
    end

    def preload(activities)
      ids = identity_ids(activities)
      ids.empty? ? {} : Identity.with_deleted.where(id: ids).index_by(&:id)
    end
  end
end
