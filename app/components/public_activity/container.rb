class Components::PublicActivity::Container < Components::Base
  register_value_helper :render_activities

  def initialize(activities)
    @activities = activities
  end

  def view_template
    table class: %i[table detailed] do
      thead do
        tr do
          th { "User" }
          th { "Action" }
          th { "Time" }
          th { "Inspect" } if Rails.env.development?
        end
      end
      tbody do
        render_activities(@activities)
      end
    end
  end
end
