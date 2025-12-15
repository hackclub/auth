class Components::Brand < Components::Base
  def initialize(identity:, logo_path: nil)
    @identity = identity
    @logo_path = logo_path
  end

  def view_template
    div(class: "brand") do
      logo
      h1 { t "brand" }
    end
    button id: "lightswitch", class: "lightswitch-btn", type: "button", "aria-label": "Toggle theme" do
      span class: "lightswitch-moon" do
        inline_icon("moon-fill", size: 16)
      end
      span class: "lightswitch-sun", style: "display: none;" do
        inline_icon("sun", size: 16)
      end
    end
    render Components::EnvironmentBanner.new
  end

  def logo
    vite_image_tag "images/hc-square.png", alt: "Hack Club logo", class: "brand-logo"
    if @logo_path
      span { "+" }
      vite_image_tag @logo_path, alt: "Logo", class: "brand-logo"
    end
  end
end
