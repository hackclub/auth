class Components::BootlegTurboButton < Components::Base
  def initialize(path, text:, **opts)
    @path = path
    @text = text
    @opts = opts
  end

  def view_template
    container_id = @opts.delete(:id) || "btb-#{@path.parameterize}"
    div(id: container_id, class: "btb-container") do
      button(
        class: "secondary small-btn",
        hx_get: @path,
        hx_target: "##{container_id}",
        hx_swap: "innerHTML",
        **@opts
      ) { @text }
      div(class: "hx-loader") do
        vite_image_tag "images/loader.gif", style: "image-rendering: pixelated;"
      end
    end
  end
end
