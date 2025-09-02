class ApplicationForm < Superform::Rails::Form
  include Phlex::Rails::Helpers::Pluralize
  include Phlex::Rails::Helpers::CheckBoxTag
  register_value_helper :program_manager_tool
  register_value_helper :super_admin_tool
  register_value_helper :mdv_tool
  register_value_helper :dev_tool

  def labeled(component, label)
    render label(class: "grid-input-1", for: component.dom.id) { label }
    span(class: "grid-input-2") { render component }
  end

  def check_box(field, description = nil)
    div class: "flex-column" do
      div class: "checkbox-row" do
        render field.checkbox
        render field.label
      end
      i { safe(description) } if description
    end
  end

  def row(component)
    div do
      render component.field.label(style: "display: block;")
      render component
    end
  end

  def around_template(&)
    super do
      error_messages
      yield
    end
  end

  def error_messages
    if model.errors.any?
      div(style: "color: red;") do
        h2 { "#{pluralize model.errors.count, "error"} prohibited this post from being saved:" }
        ul do
          model.errors.each do |error|
            li { error.full_message }
          end
        end
      end
    end
  end
end
