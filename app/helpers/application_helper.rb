module ApplicationHelper
  def format_duration(seconds)
    return "0 seconds" if seconds.nil? || seconds == 0

    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    seconds = seconds % 60

    parts = []
    parts << "#{hours} #{"hour".pluralize(hours)}" if hours > 0
    parts << "#{minutes} #{"minute".pluralize(minutes)}" if minutes > 0
    parts << "#{seconds} #{"second".pluralize(seconds)}" if seconds > 0 || parts.empty?

    parts.join(", ")
  end

  def copy_to_clipboard(clipboard_value, tooltip_direction: "n", **options, &block)
    # If block is not given, use clipboard_value as the rendered content
    block ||= ->(_) { clipboard_value }
    return yield if options.delete(:if) == false

    additional_class = options.delete(:class)
    css_classes = "pointer tooltipped tooltipped--#{tooltip_direction}#{" #{additional_class}" if additional_class}"
    tag.span "data-copy-to-clipboard": clipboard_value, class: css_classes, "aria-label": options.delete(:label) || "click to copy...", **options, &block
  end

  def render_qr_code(data, size: 200)
    require "rqrcode"

    qr = RQRCode::QRCode.new(data)
    svg = qr.as_svg(
      color: "000",
      shape_rendering: "crispEdges",
      module_size: 3,
      standalone: true,
      viewbox: true,
      svg_attributes: { class: "qr" }
    )
    svg.html_safe
  end

  def inline_icon(filename, **options)
    # cache parsed SVG files to reduce file I/O operations
    @icon_svg_cache ||= {}
    if !@icon_svg_cache.key?(filename)
      file = File.read(Rails.root.join("app", "frontend", "images", "icons", "#{filename}.svg"))
      @icon_svg_cache[filename] = Nokogiri::HTML::DocumentFragment.parse file
    end

    doc = @icon_svg_cache[filename].dup
    svg = doc.at_css "svg"
    options[:style] ||= "display: inline-flex; vertical-align: middle;"
    if options[:size]
      options[:width] ||= options[:size]
      options[:height] ||= options[:size]
      options.delete :size
    end
    options.each { |key, value| svg[key.to_s] = value }
    doc.to_html.html_safe
  end

  def emoji_image(name, alt: name)
    vite_image_tag("images/emoji/#{name}", alt: alt, style: "height: 1em; vertical-align: baseline;")
  end

  def google_places_api_script_tag
    api_key = Rails.application.credentials.dig(:google, :places_api_key)
    return unless api_key.present?

    tag.script(src: "https://maps.googleapis.com/maps/api/js?key=#{api_key}&loading=async&libraries=places&callback=onGoogleMapsLoaded", async: true, defer: true)
  end
end
