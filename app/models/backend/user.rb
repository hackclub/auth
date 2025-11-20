module Backend
  class User < ApplicationRecord
    self.table_name = "backend_users"

    belongs_to :identity, optional: true

    has_many :organizer_positions, class_name: "Backend::OrganizerPosition", foreign_key: "backend_user_id", dependent: :destroy
    has_many :organized_programs, through: :organizer_positions, source: :program, class_name: "Program"

    validates :username, presence: true, uniqueness: true

    delegate :email, :first_name, :last_name, :slack_id, to: :identity, allow_nil: true

    def active? = active
    def activate! = update!(active: true)
    def deactivate! = update!(active: false)

    def super_admin? = super_admin
    def program_manager? = program_manager
    def manual_document_verifier? = manual_document_verifier
    def human_endorser? = human_endorser
    def all_fields_access? = all_fields_access
  end
end
