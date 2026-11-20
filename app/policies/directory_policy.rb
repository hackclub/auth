# frozen_string_literal: true

class DirectoryPolicy < ApplicationPolicy
  def admin?
    user.admin?
  end
end
