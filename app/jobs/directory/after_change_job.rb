# frozen_string_literal: true

module Directory
  class AfterChangeJob < ApplicationJob
    queue_as :default

    # revocations: optional array of { identity_id:, email:, app_ids: [] }
    # pre-resolved for cases where the person/collection is already deleted
    def perform(change_ids:, revocations: nil)
      processed = Set.new

      if revocations.present?
        revocations.each do |rev|
          rev = rev.symbolize_keys
          person = Directory::Person.find_by(identity_id: rev[:identity_id])
          rev[:app_ids].each do |app_id|
            next if person && still_has_access?(person, app_id)
            key = [rev[:identity_id], app_id]
            next if processed.include?(key)
            processed << key
            revoke_tokens(rev[:identity_id], app_id)
            call_revoker(app_id, rev[:email])
          end
        end
      end

      changes = Directory::MembershipChange.where(id: change_ids, op: "removed")
      changes.each do |change|
        collection = Directory::Collection.find_by(id: change.collection_id)
        person = Directory::Person.find_by(id: change.person_id)
        next unless collection&.entitlement? && person

        identity = person.identity
        app_ids = app_ids_affected_by(collection)

        app_ids.each do |app_id|
          key = [identity.id, app_id]
          next if processed.include?(key)
          next if still_has_access?(person, app_id)
          processed << key
          revoke_tokens(identity.id, app_id)
          call_revoker(app_id, identity.primary_email)
        end
      end
    end

    private

    def still_has_access?(person, app_id)
      entitlement_ids = (
        Directory::Exposure.where(app_id: app_id).pluck(:entitlement_id) +
        Directory::AppRequirement.where(app_id: app_id).pluck(:entitlement_id)
      ).uniq
      Directory::EffectiveMembership.where(person_id: person.id, collection_id: entitlement_ids).exists?
    end

    def app_ids_affected_by(entitlement)
      exposure_apps = Directory::Exposure.where(entitlement_id: entitlement.id).pluck(:app_id)
      requirement_apps = Directory::AppRequirement.where(entitlement_id: entitlement.id).pluck(:app_id)
      (exposure_apps + requirement_apps).uniq
    end

    def revoke_tokens(identity_id, app_id)
      OAuthToken.where(resource_owner_id: identity_id, application_id: app_id)
        .where(revoked_at: nil)
        .update_all(revoked_at: Time.current)
      Doorkeeper::AccessGrant.where(resource_owner_id: identity_id, application_id: app_id)
        .where(revoked_at: nil)
        .update_all(revoked_at: Time.current)
    end

    def call_revoker(app_id, email)
      revoker = Directory::AppRevoker.find_by(app_id: app_id, enabled: true)
      return unless revoker

      Directory::RevokeSessionJob.perform_later(app_id: app_id, email: email)
    end
  end
end
