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

    def email = identity&.primary_email

    def display_name
      return username if orphaned?
      "#{first_name} #{last_name}".strip.presence || email || username || "Unknown User"
    end

    def active? = active
    def activate! = update!(active: true)
    def deactivate! = update!(active: false)

    def super_admin? = super_admin
    def program_manager? = program_manager
    def manual_document_verifier? = manual_document_verifier
    def human_endorser? = human_endorser
    def all_fields_access? = all_fields_access
    def can_break_glass? = can_break_glass

    # Returns a human-readable string of the user's roles
    def pretty_roles
      roles = []
      roles << "Super Admin" if super_admin?
      roles << "Program Manager" if program_manager?
      roles << "Manual Document Verifier" if manual_document_verifier?
      roles << "Human Endorser" if human_endorser?
      roles << "All Fields Access" if all_fields_access?
      roles.presence&.join(", ") || "None"
    end

    # Returns an array of organized program IDs
    def organized_program_ids
      organized_programs.pluck(:id)
    end

    # Sets the organized programs by IDs
    def organized_program_ids=(ids)
      ids = Array(ids).map(&:to_i).uniq
      current_ids = organized_program_ids
      # Add new organizer positions
      (ids - current_ids).each do |id|
        organizer_positions.create(program_id: id)
      end
      # Remove organizer positions not in the new list
      (current_ids - ids).each do |id|
        organizer_positions.where(program_id: id).destroy_all
      end
    end
  end
end
