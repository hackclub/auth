# frozen_string_literal: true

class Components::Backend::Banner < Components::Base
  def initialize(kind:)
    @kind = kind.to_sym
  end

  def view_template(&block)
    div(class: "tui-banner tui-banner-#{banner_class}", "box-": "square") do
      plain prefix
      plain " "
      yield
    end
  end

  private

  def banner_class
    case @kind
    when :success then "success"
    when :notice, :info then "info"
    when :warning then "warning"
    when :alert, :error, :danger then "danger"
    else "info"
    end
  end

  def prefix
    case @kind
    when :success then "[✓]"
    when :warning then "[!]"
    when :alert, :error, :danger then "[!]"
    else "[i]"
    end
  end
end
