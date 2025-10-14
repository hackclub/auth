# frozen_string_literal: true

class Components::Base < Phlex::HTML
  include Components

  # Include any helpers you want to be available across all components
  include Phlex::Rails::Helpers::Routes
  include Phlex::Rails::Helpers::FormWith
  include Phlex::Rails::Helpers::DistanceOfTimeInWords
  include Phlex::Rails::Helpers::T

  # Register Rails form helpers
  register_value_helper :form_authenticity_token
  register_value_helper :dev_tool
  register_output_helper :vite_image_tag
  register_value_helper :ap
  register_output_helper :inline_icon
  register_output_helper :copy_to_clipboard
  register_output_helper :button_tag
  register_output_helper :content_tag
  register_output_helper :link_to

  if Rails.env.development?
    def before_template
      comment { "Before #{self.class.name}" }
      super
    end
  end
end
