# frozen_string_literal: true

module Directory
  # Single source of truth for "this identity should no longer have access to this app."
  # Revokes OAuth access tokens, authorization grants, and enqueues a session revocation
  # webhook (if the app has one configured). Used by AfterChangeJob (individual revocations)
  # and bulk_revoke_non_passing (when a new requirement is added to an app).
  class RevokeAccess
    # Revoke everything for one (identity, app) pair. Idempotent — safe to call twice.
    def self.call(identity_id:, app_id:, email:)
      OAuthToken.where(resource_owner_id: identity_id, application_id: app_id)
        .where(revoked_at: nil)
        .update_all(revoked_at: Time.current)
      Doorkeeper::AccessGrant.where(resource_owner_id: identity_id, application_id: app_id)
        .where(revoked_at: nil)
        .update_all(revoked_at: Time.current)

      if Directory::AppRevoker.exists?(app_id: app_id, enabled: true)
        Directory::RevokeSessionJob.perform_later(app_id: app_id, email: email)
      end
    end

    # Bulk-revoke every token holder who doesn't meet the app's requirements.
    # Used when a new requirement is added — everyone who doesn't qualify loses access immediately.
    # Uses a SQL subselect so it doesn't materialize all identity IDs into ruby.
    def self.bulk_revoke_non_passing(app:)
      passing_identity_ids = Directory::EffectiveMembership
        .where(
          collection_id: Directory::AppRequirement.where(app_id: app.id).select(:entitlement_id)
        )
        .joins("INNER JOIN directory_people ON directory_people.id = directory_effective_memberships.person_id")
        .select("directory_people.identity_id")

      non_passing = ->(scope) {
        scope
          .where(application_id: app.id, revoked_at: nil)
          .where.not(resource_owner_id: passing_identity_ids)
      }

      tokens_to_revoke = non_passing.call(OAuthToken)
      revoked_identity_ids = tokens_to_revoke.pluck(:resource_owner_id).uniq
      tokens_to_revoke.update_all(revoked_at: Time.current)
      non_passing.call(Doorkeeper::AccessGrant).update_all(revoked_at: Time.current)

      if revoked_identity_ids.any? && Directory::AppRevoker.exists?(app_id: app.id, enabled: true)
        Identity.where(id: revoked_identity_ids).pluck(:id, :primary_email).each do |id, email|
          Directory::RevokeSessionJob.perform_later(app_id: app.id, email: email)
        end
      end

      revoked_identity_ids
    end
  end
end
