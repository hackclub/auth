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
          directory = view_context.respond_to?(:directory_activity_owner)

          if owner.nil?
            # an owner_id with no owner means a deleted identity, not the system
            i { directory && @activity.owner_id.present? ? "[deleted user]" : "System" }
          elsif directory && (owner.is_a?(::Identity) || owner.is_a?(::Backend::User))
            render view_context.directory_activity_owner(owner)
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
          plain "#{@activity.class.name} #{@activity.id}"
        end
      end
    end
  end
end
