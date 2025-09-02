class Components::BootlegTurbo < Components::Base
  def initialize(path, text: nil, **opts)
    @path = path
    @text = text
    @opts = opts
  end

  def view_template
    div(hx_get: @path, hx_trigger: :load, **@opts) do
      if @text
        plain @text
        br
      end
      vite_image_tag "images/loader.gif", class: :htmx_indicator, style: "image-rendering: pixelated;"
    end
  end
end
