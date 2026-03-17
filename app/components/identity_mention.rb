# frozen_string_literal: true

class Components::IdentityMention < Components::Base
  register_value_helper :current_identity

  def initialize(identity)
    @identity = identity
  end

  def view_template
    if @identity.nil?
      i { "System" }
      return
    end

    span(class: "identity-mention") do
      plain display_name

      if @identity.backend_user
        plain " "
        abbr(title: "#{@identity.first_name} is an admin") { "⚡" }
      end
    end
  end

  private

  def display_name
    if @identity == current_identity
      "You"
    elsif current_identity&.backend_user
      "#{@identity.first_name} #{@identity.last_name}"
    else
      @identity.first_name
    end
  end
end
