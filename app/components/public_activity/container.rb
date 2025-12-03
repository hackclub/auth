# frozen_string_literal: true

class Components::PublicActivity::Container < Components::Base
  register_value_helper :render_activities

  def initialize(activities)
    @activities = activities
  end

  def view_template
    div class: "table-container" do
      table do
        thead do
          tr do
            th { "user" }
            th { "action" }
            th { "time" }
            th { "inspect" } if Rails.env.development?
          end
        end
        tbody do
          render_activities(@activities)
        end
      end
    end
  end
end
