# frozen_string_literal: true

module Directory
  # tokens, grants, and the app's own sessions via its revoker. idempotent.
  class RevokeAccess
    def self.call(identity_id:, app_id:, email:)
      revoke_tokens(app_id: app_id, identity_ids: [ identity_id ])
      revoke_sessions([ [ app_id, email ] ])
    end

    def self.revoke_tokens(app_id:, identity_ids:)
      return if identity_ids.empty?

      now = Time.current
      OAuthToken.where(resource_owner_id: identity_ids, application_id: app_id, revoked_at: nil).update_all(revoked_at: now)
      Doorkeeper::AccessGrant.where(resource_owner_id: identity_ids, application_id: app_id, revoked_at: nil).update_all(revoked_at: now)
    end

    # pairs: [[app_id, email], ...]. One job per (revoker scope, email): Cloudflare's
    # revoke_user is account-wide, so apps on the same account share a single call. The
    # other apps in the scope ride along as fallbacks in case the first revoker is broken.
    def self.revoke_sessions(pairs)
      return if pairs.empty?

      revokers = Directory::AppRevoker.where(app_id: pairs.map(&:first).uniq, enabled: true).index_by(&:app_id)
      pairs
        .filter_map { |app_id, email| (revoker = revokers[app_id]) && [ [ revoker.session_scope_key, email.to_s.downcase ], email, app_id ] }
        .group_by(&:first)
        .each_value do |rows|
          app_ids = rows.map(&:last).uniq
          Directory::RevokeSessionJob.perform_later(app_id: app_ids.first, email: rows.first[1], fallback_app_ids: app_ids.drop(1))
        end
    end

    # Bulk-revoke every token holder who doesn't meet the app's requirements.
    # Used when an app's requirement list changes.
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

      if revoked_identity_ids.any?
        revoke_sessions(Identity.where(id: revoked_identity_ids).pluck(:primary_email).map { |email| [ app.id, email ] })
      end

      revoked_identity_ids
    end
  end
end
