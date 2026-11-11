# frozen_string_literal: true

module Directory
  class Exposure < ApplicationRecord
    has_paper_trail
    include PublicActivity::Model
    tracked owner: ->(controller, _model) { controller&.try(:user_for_public_activity) || controller&.try(:current_identity) },
            params: {
              app_name: ->(_c, model) { model.app&.name },
              entitlement_name: ->(_c, model) { model.entitlement&.name },
              claim_name: ->(_c, model) { model.claim_name }
            }

    belongs_to :app, class_name: "Program"
    belongs_to :entitlement, class_name: "Directory::Collection"
    belongs_to :created_by, class_name: "Identity", foreign_key: :created_by_identity_id, optional: true

    validates :claim_name, presence: true,
      format: { with: /\A[a-z][a-z0-9_-]*\z/, message: "must start with a lowercase letter and contain only lowercase letters, numbers, hyphens, and underscores" }
    validates :app_id, uniqueness: { scope: :entitlement_id }
    validates :claim_name, uniqueness: { scope: :app_id }
    validate :entitlement_must_be_entitlement
    validate :app_must_request_groups, on: :create

    REQUESTS_GROUPS_SQL = "' ' || %s || ' ' LIKE '%% groups %%'"

    # exposures the claim still reaches someone through: the app requests groups, or someone
    # still holds an unrevoked token issued with it. per entitlement, the same rule
    # claim_pairs applies per person, so pages and revocation agree
    REACHES_SQL = "(#{format(REQUESTS_GROUPS_SQL, 'oauth_applications.scopes')} OR EXISTS (" \
      "SELECT 1 FROM oauth_access_tokens WHERE oauth_access_tokens.application_id = directory_exposures.app_id " \
      "AND oauth_access_tokens.revoked_at IS NULL AND #{format(REQUESTS_GROUPS_SQL, 'oauth_access_tokens.scopes')}))"

    def self.reaching = joins(:app).where(REACHES_SQL)

    # [app_id, identity_id] pairs where the groups claim reaches that person in that app: the
    # app requests groups now, or the person still holds an unrevoked token issued with it
    # (after a downgrade the old tokens and id_tokens keep carrying the claim)
    def self.claim_pairs(app_ids:, identity_ids:)
      app_ids = app_ids.uniq
      identity_ids = identity_ids.uniq
      return Set.new if app_ids.empty? || identity_ids.empty?

      requesting = Program.where(id: app_ids).where(format(REQUESTS_GROUPS_SQL, "oauth_applications.scopes")).pluck(:id)
      pairs = requesting.product(identity_ids).to_set
      OAuthToken.where(application_id: app_ids - requesting, resource_owner_id: identity_ids, revoked_at: nil)
        .where(format(REQUESTS_GROUPS_SQL, "oauth_access_tokens.scopes"))
        .distinct.pluck(:application_id, :resource_owner_id)
        .each { |pair| pairs << pair }
      pairs
    end

    def self.claim_names_for(person:, app:)
      where(app_id: app.id)
        .where(entitlement_id: Directory::EffectiveMembership.where(person_id: person.id).select(:collection_id))
        .pluck(:claim_name)
    end

    private

    def app_must_request_groups
      return unless app

      errors.add(:base, "this app doesn't request the groups scope, so it would never receive the claim. ask an admin to add the scope first") unless app.has_scope?(:groups)
    end

    def entitlement_must_be_entitlement
      return unless entitlement

      errors.add(:entitlement, "must be an entitlement") unless entitlement&.entitlement?
    end
  end
end
