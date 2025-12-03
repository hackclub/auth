# params.require(:backend_user).permit(:username, :icon_url, :all_fields_access, :human_endorser, :program_manager, :manual_document_verifier, :super_admin, :can_break_glass, organized_program_ids: [])

class Backend::Users::Form < ApplicationForm
  def view_template(&)
    unless model.orphaned?
      div class: "card margin-bottom" do
        h4 { "Linked Identity" }
        p { b { "Name: " }; "#{model.first_name} #{model.last_name}" }
        p { b { "Email: " }; model.email }
        p { b { "Slack ID: " }; model.slack_id || "Not linked" }
      end
    end

    if model.orphaned?
      div do
        labeled field(:username).input, "Display Name: "
      end
    end

    render ::Backend::Users::PermissionsForm.new(model)

    submit "save"
  end
end
