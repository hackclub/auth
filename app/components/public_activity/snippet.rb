# frozen_string_literal: true

class Components::PublicActivity::Snippet < Components::Base
  def initialize(activity, owner: nil, owner_component: nil)
    @activity = activity
    @owner = owner
    @owner_component = owner_component
  end

  def view_template
    tr do
      td do
        if @owner_component
          render @owner_component
        else
          owner = @owner || @activity.owner

          if owner.nil?
            i { "System" }
          elsif owner.is_a?(::Backend::User) || owner.is_a?(::Identity)
            render Components::UserMention.new(owner)
          elsif owner.is_a?(::Program)
            a(href: helpers.developer_app_path(owner)) { plain owner.name }
          else
            plain "#{owner.class.name} #{owner.try(:public_id) || owner.id}"
          end
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
