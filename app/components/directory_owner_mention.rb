# frozen_string_literal: true

class Components::DirectoryOwnerMention < Components::Base
  def initialize(name:, href: nil)
    @name = name
    @href = href
  end

  def view_template
    span class: "user-mention" do
      if @href
        a(href: @href) { plain @name }
      else
        plain @name
      end
    end
  end
end
