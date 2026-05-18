# frozen_string_literal: true

class DeletionPolicy < ApplicationPolicy
  def index?
    user.present? && user.can_process_deletions?
  end

  def show? = index?
  def create? = index?
end
