# frozen_string_literal: true

class Components::Banner < Components::Base
  def initialize(kind:, event_id: nil)
    @kind = kind
    @event_id = event_id
  end

  def view_template(&block)
    div(class: "banner flex #{banner_class}") do
      render_icon
      div(class: "flex-1") do
        yield
        render_event_id if @event_id.present?
      end
    end
  end

  private

  def render_event_id
    div(class: "error-id-container mt-1") do
      small(class: "error-id-text text-sm opacity-75") do
        plain "Error ID: "
        code(
          class: "error-id-code cursor-pointer hover:opacity-80",
          data_error_id: @event_id,
          onclick: "copyErrorId(this)",
          title: "Click to copy"
        ) { @event_id }
        span(class: "copy-feedback ml-1 hidden") { " ✓ Copied!" }
      end
    end
  end

  def banner_class
    case @kind.to_sym
    when :success then "success"
    when :notice, :info then "info"
    when :warning then "warning"
    when :alert, :error, :danger then "danger"
    else "info"
    end
  end

  def render_icon
    svg(
      xmlns: "http://www.w3.org/2000/svg",
      class: "h-5 w-5 mr-2",
      fill: "none",
      viewBox: "0 0 24 24",
      stroke: "currentColor"
    ) do |s|
      case @kind.to_sym
      when :success
        s.path(
          stroke_linecap: "round",
          stroke_linejoin: "round",
          stroke_width: "2",
          d: "M5 13l4 4L19 7"
        )
      when :notice, :info
        s.path(
          stroke_linecap: "round",
          stroke_linejoin: "round",
          stroke_width: "2",
          d: "M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
        )
      when :warning, :alert, :error, :danger
        s.path(
          stroke_linecap: "round",
          stroke_linejoin: "round",
          stroke_width: "2",
          d: "M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
        )
      end
    end
  end
end
