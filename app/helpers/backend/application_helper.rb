module Backend::ApplicationHelper
  def render_checkbox(value)
    symbol = value ? "☑" : "☐"
    color = "var(--checkbox-#{value ? "true" : "false"})"
    content_tag(:span, symbol, style: "color: #{color}; font-size: 1.3em")
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

  def glass_broken?(break_glassable, auto_break_glass: nil)
    return false unless current_user

    existing = BreakGlassRecord.for_user_and_document(current_user, break_glassable).recent.exists?
    return true if existing

    if auto_break_glass
      BreakGlassRecord.create!(
        backend_user: current_user,
        break_glassable: break_glassable,
        reason: auto_break_glass,
        accessed_at: Time.current,
        automatic: true,
      )
      return true
    end

    false
  end

  def render_nav_item(path, label, code, variant: "background2", sub: nil)
    content_tag(:a, href: path, "data-navigable-item": true,
      style: "display: flex; justify-content: space-between; align-items: center; padding: 0 1ch; text-decoration: none; color: var(--text);") do
      left = content_tag(:span) do
        concat label
        concat " ".html_safe + content_tag(:i, sub, style: "color: var(--overlay0);") if sub
      end
      right = content_tag(:span, code, "is-": "badge", "variant-": variant, )
      left + right
    end
  end

  def break_glass_document_type(break_glassable)
    case break_glassable.class.name
    when "Identity::Document" then "identity document"
    when "Identity::AadhaarRecord" then "aadhaar record"
    else "document"
    end
  end
end
