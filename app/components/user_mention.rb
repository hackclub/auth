# frozen_string_literal: true

class Components::UserMention < Components::Base
  extend Literal::Properties

  prop :user, _Union(::Backend::User, ::Identity), :positional

  def view_template
    div class: "icon", role: "option" do
      case @user
      when ::Backend::User
        img src: @user.icon_url, width: "16px", class: "inline pr-2"
        div class: "icon-label" do
          a(href: backend_user_path(@user)) do
            span { @user.username }
            span { inline_icon("bolt", size: 12) } if @user.super_admin?
          end
        end
      when ::Identity
        div(class: "inline pr-2") { inline_icon("card-id", size: 16) }
        div class: "icon-label" do
          a(href: backend_identity_path(@user)) { span { "#{@user.first_name} #{@user.last_name}" } }
        end
      end
    end
  end
end
