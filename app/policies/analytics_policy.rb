# frozen_string_literal: true

class AnalyticsPolicy < ApplicationPolicy
  def show?
    # Allow document verifiers and admins to view analytics
    user_is_manual_document_verifier?
  end
end
