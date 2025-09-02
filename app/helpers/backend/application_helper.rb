module Backend::ApplicationHelper
  def render_checkbox(value)
    content_tag(:span, style: "color: var(--checkbox-#{value ? "true" : "false"})") { value ? "☑" : "☒" }
  end

  def super_admin_tool(class_name: "", element: "div", **options, &block)
    return unless current_user&.super_admin?
    concat content_tag(element, class: "super-admin-tool #{class_name}", **options, &block)
  end

  def break_glass_tool(class_name: "", element: "div", **options, &block)
    return unless current_user&.can_break_glass? || current_user&.super_admin?
    concat content_tag(element, class: "break-glass-tool #{class_name}", **options, &block)
  end

  def program_manager_tool(class_name: "", element: "div", **options, &block)
    return unless current_user&.program_manager? || current_user&.super_admin?
    concat content_tag(element, class: "program-manager-tool #{class_name}", **options, &block)
  end

  def mdv_tool(class_name: "", element: "div", **options, &block)
    return unless current_user&.manual_document_verifier? || current_user&.super_admin?
    concat content_tag(element, class: "mdv-tool #{class_name}", **options, &block)
  end

  def dev_tool(class_name: "", element: "div", **options, &block)
    return unless Rails.env.development?
    concat content_tag(element, class: "dev-tool #{class_name}", **options, &block)
  end
end
