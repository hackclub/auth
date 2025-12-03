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

        if owner.nil?
          i { "unknown" }
        elsif owner.is_a?(::Backend::User)
          render Components::UserMention.new(owner)
        elsif owner.is_a?(::Identity)
          render Components::UserMention.new(owner)
        else
          render owner
        end
      end
      td { yield }
      td { @activity.created_at.strftime("%Y-%m-%d %H:%M") }
      if Rails.env.development?
        td do
          render Components::Inspector.new(@activity, small: true)
        end
      end
    end
  end
end
