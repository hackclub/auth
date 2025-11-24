class Components::Brand < Components::Base
  def initialize(identity:)
    @identity = identity
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
  end
end
