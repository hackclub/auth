# frozen_string_literal: true

class Components::PublicActivity::Snippet < Components::Base
  def initialize(activity, owner: nil)
    @activity = activity
    @owner = owner
  end

  def view_template
    tr do
      td { render @owner || @activity.owner }
      td { yield }
      td { @activity.created_at.strftime("%Y-%m-%d %H:%M:%S") }
      td do
        if Rails.env.development?
          render Components::Inspector.new(@activity, small: true)
          render Components::Inspector.new(@activity.trackable, small: true)
        end
      end
    end
  end
end
