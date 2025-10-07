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
      h1 { "Hack Club Account" }
    end
    button id: "lightswitch", class: "lightswitch-btn", type: "button", "aria-label": "Toggle theme" do
      span class: "lightswitch-icon" do
        "🌙"
      end
    end
    render Components::EnvironmentBanner.new
  end

  def logo
    vite_image_tag "images/hc-square.png", alt: "Hack Club logo", class: "brand-logo"
  end
end
