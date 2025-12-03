module Backend
  class User < ApplicationRecord
    self.table_name = "backend_users"

    belongs_to :identity, optional: true

    has_many :organizer_positions, class_name: "Backend::OrganizerPosition", foreign_key: "backend_user_id", dependent: :destroy
    has_many :organized_programs, through: :organizer_positions, source: :program, class_name: "Program"

    validates :username, presence: true, uniqueness: true, if: :orphaned?

    delegate :first_name, :last_name, :slack_id, to: :identity, allow_nil: true

    scope :orphaned, -> { where(identity_id: nil) }
    scope :linked, -> { where.not(identity_id: nil) }

    def orphaned? = identity_id.nil?

    def display_name
      return username if orphaned?
      "#{first_name} #{last_name}".strip.presence || email || username
    end

    def email = identity.primary_email

    def active? = active
    def activate! = update!(active: true)
    def deactivate! = update!(active: false)

    def super_admin? = super_admin
    def program_manager? = program_manager
    def manual_document_verifier? = manual_document_verifier
    def human_endorser? = human_endorser
    def all_fields_access? = all_fields_access

    def pretty_roles
      return "Super admin" if super_admin?
      roles = []
      roles << "Program manager" if program_manager?
      roles << "Document verifier" if manual_document_verifier?
      roles << "Endorser" if human_endorser?
      roles << "All fields" if all_fields_access?
      roles.join(", ")
    end
  end
end
