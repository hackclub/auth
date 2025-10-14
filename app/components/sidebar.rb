# frozen_string_literal: true

class Components::Sidebar < Components::Base
  include Phlex::Rails::Helpers::LinkTo
  include Phlex::Rails::Helpers::CurrentPage

  register_value_helper :current_identity
  register_value_helper :signed_in?
  register_value_helper :root_path
  register_value_helper :logout_path
  register_output_helper :copy_to_clipboard
  register_output_helper :vite_image_tag

  def initialize(current_path:)
    @current_path = current_path
  end

  def view_template
    render_mobile_toggle
    render_overlay

    nav(class: "sidebar", id: "sidebar") do
      render_sidebar_brand
      render_navigation
      render_user_section if signed_in?
    end

    render_toggle_script
  end

  private

  def nav_items
    items = [
      { label: t("sidebar.home"), path: root_path, icon: "home" }
    ]

    items << { label: t("sidebar.edit_info"), path: edit_identity_path, icon: "person" }

    # Add verification link if user needs to submit or resubmit
    if current_identity.present?
      status = current_identity.verification_status
      if status == "needs_submission" || status == "pending"
        items << {
          label: t("sidebar.verification"),
          path: new_verifications_path,
          icon: status == "pending" ? "clock" : "card-id"
        }
      end
    end

    items << { label: t("sidebar.addresses"), path: addresses_path, icon: "email" }
    items << { label: t("sidebar.security"), path: security_path, icon: "private" }

    # Add developer link if developer mode is enabled
    if current_identity.present? && current_identity.developer_mode?
      items << { label: t("sidebar.developer"), path: developer_apps_path, icon: "code" }
    end

    items
  end

  def render_mobile_toggle
    button(class: "sidebar-toggle", onclick: safe("toggleSidebar()"), "aria-label": "Toggle sidebar") do
      svg(
        width: "24",
        height: "24",
        viewBox: "0 0 24 24",
        fill: "none",
        stroke: "currentColor",
        stroke_width: "2.5",
        stroke_linecap: "round",
        stroke_linejoin: "round"
      ) do |s|
        s.line(x1: "4", y1: "6", x2: "20", y2: "6")
        s.line(x1: "4", y1: "12", x2: "20", y2: "12")
        s.line(x1: "4", y1: "18", x2: "20", y2: "18")
      end
    end
  end

  def render_overlay
    div(class: "sidebar-overlay", onclick: safe("toggleSidebar()"))
  end

  def render_navigation
    div(class: "sidebar-nav") do
      nav_items.each do |item|
        render_nav_item(**item)
      end
    end
  end

  def render_nav_item(label:, path:, icon: nil)
    is_active = @current_path == path

    link_to(path, class: [ "sidebar-nav-item", ("active" if is_active) ].compact.join(" ")) do
      span(class: "nav-icon") { helpers.inline_icon(icon, size: 24) } if icon
      span(class: "nav-label") { label }
    end
  end

  def render_user_section
    div(class: "sidebar-user") do
      render_user_info
      render_logout_button
    end
  end

  def render_user_info
    div(class: "user-info") do
      copy_to_clipboard current_identity.public_id, tooltip_direction: "e", label: "click to copy your account ID..." do
        div(class: "user-avatar") do
          span { current_identity.first_name&.first || "?" }
        end
      end
      div(class: "user-details") do
        div(class: "user-name") do
          plain current_identity.first_name
          whitespace
          plain current_identity.last_name
        end
        div(class: "user-email") { current_identity.primary_email }
      end
    end
  end

  def render_logout_button
    form_with(url: logout_path, method: :delete, class: "logout-form") do
      button(type: "submit", class: "logout-button") do
        plain t "sidebar.logout"
        span(class: "logout-icon") { helpers.inline_icon("door-leave", size: 18) }
      end
    end
  end

  def render_sidebar_brand
    div(class: "sidebar-brand") do
      vite_image_tag("images/hc-square.png", alt: "Hack Club logo", class: "brand-logo")
      h1 { I18n.t(".brand") }
      button(id: "lightswitch", class: "lightswitch-btn", type: "button", "aria-label": "Toggle theme") do
        span(class: "lightswitch-moon") { helpers.inline_icon("moon-fill", size: 16) }
        span(class: "lightswitch-sun", style: "display: none;") { helpers.inline_icon("sun", size: 16) }
      end
    end
    render Components::EnvironmentBanner.new
  end

  def render_toggle_script
    script do
      raw safe <<~JS
        function toggleSidebar() {
          const sidebar = document.getElementById('sidebar');
          const overlay = document.querySelector('.sidebar-overlay');
          sidebar.classList.toggle('mobile-open');
          overlay.classList.toggle('active');
        }
      JS
    end
  end
end
