# frozen_string_literal: true

module Directory
  class AfterChangeJob < ApplicationJob
    queue_as :default

    def perform(change_ids:)
      changes = Directory::MembershipChange.where(id: change_ids, op: "removed")
      changes.each do |change|
        collection = Directory::Collection.find_by(id: change.collection_id)
        person = Directory::Person.find_by(id: change.person_id)
        next unless collection&.entitlement? && person

        identity = person.identity
        app_ids = app_ids_affected_by(collection)

        app_ids.each do |app_id|
          revoke_tokens(identity, app_id)
          call_revoker(app_id, identity.primary_email)
        end
      end
    end

    private

    def app_ids_affected_by(entitlement)
      exposure_apps = Directory::Exposure.where(entitlement_id: entitlement.id).pluck(:app_id)
      requirement_apps = Directory::AppRequirement.where(entitlement_id: entitlement.id).pluck(:app_id)
      (exposure_apps + requirement_apps).uniq
    end

    def revoke_tokens(identity, app_id)
      OAuthToken.where(resource_owner_id: identity.id, application_id: app_id)
        .where(revoked_at: nil)
        .update_all(revoked_at: Time.current)
      Doorkeeper::AccessGrant.where(resource_owner_id: identity.id, application_id: app_id)
        .where(revoked_at: nil)
        .update_all(revoked_at: Time.current)
    end

    def call_revoker(app_id, email)
      revoker = Directory::AppRevoker.find_by(app_id: app_id, enabled: true)
      return unless revoker

      Directory::Revokers.for(revoker).call(email: email)
      revoker.update(last_called_at: Time.current, last_result: "ok")
    rescue => e
      revoker.update(last_called_at: Time.current, last_result: "failed: #{e.message}")
      Rails.logger.error("[Directory] Revoker failed for app #{app_id}: #{e.message}")
    end
  end
end
