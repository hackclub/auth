# frozen_string_literal: true

class Components::PublicActivity::Snippet < Components::Base
  def initialize(activity, owner: nil)
    @activity = activity
    @owner = owner
  end

  def view_template
    tr do
      td do
        owner = @owner || @activity.owner
        # Only render backend users as links if current user is a backend user
        # Check if we're in the backend context by looking for current_user helper
        is_backend = respond_to?(:current_user) && current_user.is_a?(Backend::User)

        if owner.is_a?(Backend::User) && !is_backend
          plain owner.username
        else
          render owner
        end
      end
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
