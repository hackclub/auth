# frozen_string_literal: true

class Backend::Users::PermissionsForm < ApplicationForm
  def view_template(&)
    b { "Roles: " }
    div class: "grid gap align-center", style: "grid-template-columns: max-content auto;" do
      check_box(field(:super_admin), "Allows this user access to all permissions<br/> (this includes managing other users)")
      check_box(field(:program_manager), "This user can provision API keys and program tags.")
      check_box(field(:human_endorser), "This user can mark identities as <br/>human-endorsed.")
      check_box(field(:all_fields_access), "This user can view all fields on all identities.")
      check_box(field(:manual_document_verifier), "This user can mark documents as<br/>manually verified.")
      check_box(field(:can_break_glass), "This user can view ID docs after they've been reviewed.")
    end

    b { "Program Organizer Positions: " }
    div class: "grid gap", style: "grid-template-columns: 1fr;" do
      Program.all.each do |program|
        is_organizer = model.organized_programs.include?(program)

        div class: "flex-column" do
          div class: "checkbox-row" do
            check_box_tag("backend_user[organized_program_ids][]", program.id, is_organizer, id: "organized_program_#{program.id}")
            label(for: "organized_program_#{program.id}") { program.name }
          end
        end
      end
    end
  end
end
