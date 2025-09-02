class Components::Brand < Components::Base
  def initialize(identity:)
    @identity = identity
  end

  def view_template
    div(class: "brand") do
      if @identity.present?
        copy_to_clipboard @identity.public_id, tooltip_direction: "e", label: "click to copy your internal ID" do
          logo
        end
      else
        logo
      end
      h1 { "Hack Club Identity" }
    end
    button id: "lightswitch", class: "lightswitch-btn", type: "button", "aria-label": "Toggle theme" do
      span class: "lightswitch-icon" do
        "🌙"
      end
    end
    case Rails.env
    when "staging"
      div(class: "banner purple") do
        safe "this is a staging environment. <b>do not upload any actual personal information here.<b>"
      end
    when "development"
      div(class: "banner success") do
        plain "you're in dev! go nuts :3"
      end
    end
  end

  def logo
    vite_image_tag "images/hc-square.png", alt: "Hack Club logo", class: "brand-logo"
  end
end
