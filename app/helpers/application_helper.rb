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

    css_classes = "pointer tooltipped tooltipped--#{tooltip_direction} #{options.delete(:class)}"
    tag.span "data-copy-to-clipboard": clipboard_value, class: css_classes, "aria-label": options.delete(:label) || "click to copy...", **options, &block
  end
end
