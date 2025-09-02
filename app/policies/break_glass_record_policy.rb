# frozen_string_literal: true

class BreakGlassRecordPolicy < ApplicationPolicy
  def create? = user.present? && user.can_break_glass?
end
