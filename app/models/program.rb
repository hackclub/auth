# == Schema Information
#
# Table name: oauth_applications
#
#  id                     :bigint           not null, primary key
#  active                 :boolean          default(TRUE)
#  confidential           :boolean          default(TRUE), not null
#  name                   :string           not null
#  program_key_bidx       :string
#  program_key_ciphertext :text
#  redirect_uri           :text             not null
#  scopes                 :string           default(""), not null
#  secret                 :string           not null
#  uid                    :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
# Indexes
#
#  index_oauth_applications_on_program_key_bidx  (program_key_bidx) UNIQUE
#  index_oauth_applications_on_uid               (uid) UNIQUE
#
class Program < ApplicationRecord
  self.table_name = "oauth_applications"

  include PublicActivity::Model
  tracked owner: ->(controller, _model) { controller&.user_for_public_activity }, only: [ :create ]

  include Auditable

  audit_field :name, label: "app name"
  audit_field :trust_level, transform: ->(v) { v.to_s.titleize }
  audit_field :scopes_array, type: :array, label: "scopes"
  audit_field :redirect_uris, type: :array, label: "redirect URIs"
  audit_field :active, type: :boolean
  audit_field :onboarding_scenario, transform: ->(v) { v&.titleize }

  COLLABORATOR_ACTIVITY_KEYS = %w[
    program.collaborator_invited
    program.collaborator_removed
    program.collaborator_accepted
    program.collaborator_declined
    program.collaborator_cancelled
  ].freeze

  has_paper_trail

  include ::Doorkeeper::Orm::ActiveRecord::Mixins::Application

  enum :trust_level, { hq_official: 0, community_untrusted: 1, community_trusted: 2 }, default: :hq_official

  scope :official, -> { where(trust_level: :hq_official) }

  AVAILABLE_SCOPES = OAuthScope::ALL.map { |s| { name: s.name, description: s.description } }.freeze
  COMMUNITY_ALLOWED_SCOPES = OAuthScope::COMMUNITY_ALLOWED

  has_many :access_grants, class_name: "Doorkeeper::AccessGrant", foreign_key: :application_id, dependent: :delete_all
  has_many :identities, through: :access_grants, source: :resource_owner, source_type: "Identity"

  has_many :organizer_positions, class_name: "Backend::OrganizerPosition", foreign_key: :program_id, dependent: :destroy
  has_many :organizers, through: :organizer_positions, source: :backend_user, class_name: "Backend::User"

  has_many :program_collaborators, dependent: :destroy
  has_many :collaborator_identities, -> { merge(ProgramCollaborator.accepted) },
           through: :program_collaborators, source: :identity

  belongs_to :owner_identity, class_name: "Identity", optional: true

  validates :name, presence: true
  validates :uid, presence: true, uniqueness: true
  validates :secret, presence: true
  validates :redirect_uri, presence: true
  validates :scopes, presence: true
  validate :validate_community_scopes

  before_validation :generate_uid, on: :create
  before_validation :generate_secret, on: :create
  before_validation :generate_program_key, on: :create

  has_encrypted :program_key
  blind_index :program_key

  def oauth_application = self

  # i forget why this is like this:
  alias_method :application_id, :id

  def description = nil
  def description? = false

  def description=(value)
  end

  # </forgetting why this is like this>

  def scopes_array
    return [] if scopes.blank?
    scopes.to_a
  end

  def scopes_array=(array)
    self.scopes = Doorkeeper::OAuth::Scopes.from_array(Array(array).reject(&:blank?)).to_s
  end

  def redirect_uris
    redirect_uri.to_s.split
  end

  def has_scope?(scope_name) = scopes.include?(scope_name.to_s)

  def authorized_for_identity?(identity) = authorized_tokens.exists?(resource_owner: identity)

  def onboarding_scenario_class
    return nil if onboarding_scenario.blank?
    OnboardingScenarios::Base.find_by_slug(onboarding_scenario)
  end

  def onboarding_scenario_instance(identity = nil)
    onboarding_scenario_class&.new(identity)
  end

  def collaborator?(identity)
    return false unless identity
    program_collaborators.accepted.exists?(identity: identity)
  end

  def accessible_by?(identity)
    return false unless identity
    owner_identity_id == identity.id || collaborator?(identity)
  end

  def rotate_credentials!
    self.secret = SecureRandom.hex(32)
    self.program_key = "prgmk." + SecureRandom.hex(32)
    save!
  end

  def self.find_by_redirect_uri_host(url)
    return nil if url.blank?
    begin
      uri = URI.parse(url)
      host = uri.host
      return nil unless host

      matching_programs = []
      find_each do |program|
        program.redirect_uri.to_s.split("\n").each do |redirect_uri|
          begin
            redirect_host = URI.parse(redirect_uri.strip).host
            if redirect_host == host
              matching_programs << program
              break
            end
          rescue URI::InvalidURIError
            next
          end
        end
      end

      # Prefer programs with onboarding scenarios set
      matching_programs.find { |p| p.onboarding_scenario.present? } || matching_programs.first
    rescue URI::InvalidURIError
      nil
    end
  end

  private

  def validate_community_scopes
    return if hq_official?

    invalid_scopes = scopes_array - COMMUNITY_ALLOWED_SCOPES
    if invalid_scopes.any?
      errors.add(:scopes, "Community apps can only use these scopes: #{COMMUNITY_ALLOWED_SCOPES.join(', ')}")
    end
  end

  def generate_uid
    self.uid = SecureRandom.hex(16) if uid.blank?
  end

  def generate_secret
    self.secret = SecureRandom.hex(32) if secret.blank?
  end

  def generate_program_key
    self.program_key = "prgmk." + SecureRandom.hex(32) if program_key.blank?
  end
end
