class Backend::Programs::Form < ApplicationForm
  def view_template(&)
    div do
      labeled field(:name).input, "Program Name: "
    end
    div do
      label(class: "field-label") { "Redirect URIs (one per line):" }
      textarea(
        name: "oauth_application[redirect_uri]",
        placeholder: "https://example.com/callback",
        class: "input-field",
        rows: 3,
        style: "width: 100%;",
      ) { model.redirect_uri }
    end
    program_manager_tool do
      div style: "margin: 1rem 0;" do
        label(class: "field-label") { "OAuth Scopes:" }
        # Hidden field to ensure empty scopes array is submitted when no checkboxes are checked
        input type: "hidden", name: "program[scopes_array][]", value: ""
        Program::AVAILABLE_SCOPES.each do |scope|
          div class: "checkbox-row" do
            scope_checked = model.persisted? ? model.has_scope?(scope[:name]) : false
            input(
              type: "checkbox",
              name: "program[scopes_array][]",
              value: scope[:name],
              id: "program_scopes_#{scope[:name]}",
              checked: scope_checked,
            )
            label(for: "program_scopes_#{scope[:name]}", class: "checkbox-label", style: "margin-right: 0.5rem;") { scope[:name] }
            small { scope[:description] }
          end
        end
      end
    end

    submit model.new_record? ? "Create Program" : "Update Program"
  end
end
