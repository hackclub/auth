# frozen_string_literal: true

class AuditLogPolicy < ApplicationPolicy
  def index? = user.present? && user.super_admin?
end
