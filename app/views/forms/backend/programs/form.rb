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
        label(class: "field-label") { "Trust Level:" }
        select(
          name: "program[trust_level]",
          class: "input-field",
          style: "width: 100%; margin-bottom: 1rem;"
        ) do
          Program.trust_levels.each do |key, value|
            option(
              value: key,
              selected: model.trust_level == key
            ) { key.titleize }
          end
        end
      end

      super_admin_tool do
        div style: "margin: 1rem 0;" do
          label(class: "field-label") { "Onboarding Scenario:" }
          select(
            name: "program[onboarding_scenario]",
            class: "input-field",
            style: "width: 100%; margin-bottom: 1rem;"
          ) do
            option(value: "", selected: model.onboarding_scenario.blank?) { "(default)" }
            OnboardingScenarios::Base.available_slugs.each do |slug|
              option(
                value: slug,
                selected: model.onboarding_scenario == slug
              ) { slug.titleize }
            end
          end
          small(style: "display: block; color: var(--muted-color); margin-top: -0.5rem;") do
            plain "When users sign up through this OAuth app, they'll use this onboarding flow"
          end
        end
      end

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
