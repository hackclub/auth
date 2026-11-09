# frozen_string_literal: true

module Directory
  # Runs after a rebuild commits. Processes "removed" effective membership changes:
  # for each person who lost an entitlement, checks if they still qualify for each affected
  # app (via another entitlement), and revokes access if not. Deduplicates across the two
  # input sources (pre-resolved revocations + change records) to avoid double-revoking.
  class AfterChangeJob < ApplicationJob
    queue_as :default

    # revocations: pre-resolved { identity_id, email, app_ids, entitlement_ids? } for entities
    #   that may be deleted by the time this job runs (person removed, collection deleted).
    #   entitlement_ids names the entitlements that were lost; when absent (collection or
    #   person deleted) the loss is treated as permanent.
    # change_ids: IDs in membership_changes table for the rebuild diff.
    def perform(change_ids:, revocations: nil)
      candidates = revocation_candidates(revocations) + change_candidates(change_ids)
      return if candidates.empty?

      preload(candidates)

      # app_id => { identity_id => email }
      to_revoke = Hash.new { |h, k| h[k] = {} }
      candidates.each do |c|
        next if to_revoke[c[:app_id]].key?(c[:identity_id])
        next if c[:person] && c[:lost_ids] && still_has_access?(c[:person], c[:app_id], c[:lost_ids])

        to_revoke[c[:app_id]][c[:identity_id]] = c[:email]
      end

      to_revoke.each { |app_id, emails| Directory::RevokeAccess.revoke_tokens(app_id: app_id, identity_ids: emails.keys) }
      Directory::RevokeAccess.revoke_sessions(to_revoke.flat_map { |app_id, emails| emails.values.map { |email| [ app_id, email ] } })
    end

    private

    def revocation_candidates(revocations)
      return [] if revocations.blank?

      revocations = revocations.map(&:symbolize_keys)
      people = Directory::Person.where(identity_id: revocations.map { |r| r[:identity_id] }.uniq).index_by(&:identity_id)

      revocations.flat_map do |rev|
        rev[:app_ids].map do |app_id|
          { identity_id: rev[:identity_id], email: rev[:email], app_id: app_id,
            person: people[rev[:identity_id]], lost_ids: rev[:entitlement_ids] }
        end
      end
    end

    def change_candidates(change_ids)
      changes = Directory::MembershipChange.where(id: change_ids, op: "removed").pluck(:person_id, :collection_id)
      return [] if changes.empty?

      entitlement_ids = Directory::Collection.where(id: changes.map(&:last).uniq, kind: "entitlement").pluck(:id).to_set
      changes.select! { |_, collection_id| entitlement_ids.include?(collection_id) }
      return [] if changes.empty?

      app_ids_by_entitlement = Directory::Collection.affected_app_ids_by_entitlement(entitlement_ids.to_a)
      people = Directory::Person.where(id: changes.map(&:first).uniq).includes(:identity).index_by(&:id)

      changes.flat_map do |person_id, collection_id|
        person = people[person_id]
        next [] unless person

        (app_ids_by_entitlement[collection_id] || []).map do |app_id|
          { identity_id: person.identity_id, email: person.identity.primary_email, app_id: app_id,
            person: person, lost_ids: [ collection_id ] }
        end
      end
    end

    # Everything still_has_access? needs, in three queries instead of a few per person.
    def preload(candidates)
      app_ids = candidates.map { |c| c[:app_id] }.uniq
      @requirements = Directory::AppRequirement.where(app_id: app_ids).pluck(:app_id, :entitlement_id)
        .group_by(&:first).transform_values { |rows| rows.map(&:last).to_set }
      @exposures = Directory::Exposure.where(app_id: app_ids).pluck(:app_id, :entitlement_id)
        .group_by(&:first).transform_values { |rows| rows.map(&:last).to_set }

      relevant = (@requirements.values + @exposures.values).reduce(Set.new, :|)
      person_ids = candidates.filter_map { |c| c[:person]&.id }.uniq
      @held = Directory::EffectiveMembership.where(person_id: person_ids, collection_id: relevant.to_a)
        .pluck(:person_id, :collection_id)
        .group_by(&:first).transform_values { |rows| rows.map(&:last).to_set }
    end

    # Can this person keep their existing tokens for this app after losing lost_ids?
    # No if they no longer meet the app's requirements (any-of), or if they no longer hold
    # a lost entitlement that the app receives as a groups claim — the id_token they hold
    # still carries it, so they have to re-authorize to get a truthful claim.
    def still_has_access?(person, app_id, lost_ids)
      held = @held.fetch(person.id, Set.new)

      requirement_ids = @requirements.fetch(app_id, Set.new)
      return false if requirement_ids.any? && !held.intersect?(requirement_ids)

      exposed_ids = @exposures.fetch(app_id, Set.new)
      lost_ids.none? { |id| !held.include?(id) && exposed_ids.include?(id) }
    end
  end
end
