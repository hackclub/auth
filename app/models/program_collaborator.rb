# frozen_string_literal: true

class ProgramCollaborator < ApplicationRecord
  belongs_to :program
  belongs_to :identity

  validates :identity_id, uniqueness: { scope: :program_id }
end
