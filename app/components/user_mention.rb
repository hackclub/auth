# frozen_string_literal: true

class Components::UserMention < Components::Base
  extend Literal::Properties

  prop :user, _Union(::Backend::User, ::Identity), :positional

  def view_template
    span class: "user-mention" do
      case @user
      when ::Backend::User
        a(href: backend_user_path(@user)) do
          plain @user.username
          plain " ⚡" if @user.super_admin?
        end
      when ::Identity
        a(href: backend_identity_path(@user)) do
          plain "#{@user.first_name} #{@user.last_name}"
        end
      end
    end
  end
end
