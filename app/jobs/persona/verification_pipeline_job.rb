# frozen_string_literal: true

class Persona::VerificationPipelineJob < ApplicationJob
  queue_as :default

  def perform(verification)
    @verification = verification
    return if @verification.approved? || @verification.rejected?

    @identity = verification.identity
    @record = verification.persona_record

    run_resemblances
    @identity.reload
    run_decisioning
  end

  private

  def document_names
    return [] unless @record&.name_first.present? && @record&.name_last.present?

    [ { first: @record.name_first, last: @record.name_last, dob: @record.birthdate } ]
  end

  def run_resemblances
    ResemblanceNoticerEngine.run(@identity, additional_names: document_names)
  end

  def run_decisioning
    verdict = Internal::Decisioning.run(@verification)

    case verdict
    when :approved
      if !@verification.auto_approvable?
        @verification.update(issues: @verification.issues + [ "Student ID — requires manual review" ])
        Slack::NotifyReviewQueueJob.perform_later(@verification)
      elsif @record&.birthdate && Identity.calculate_age(@record.birthdate) < 13
        @verification.update(issues: @verification.issues + [ "Under 13 — requires manual review" ])
        Slack::NotifyReviewQueueJob.perform_later(@verification)
      elsif @identity.resemblances.any?
        @verification.update(issues: @verification.issues + [ "Resemblance detected — requires manual review" ])
        Slack::NotifyReviewQueueJob.perform_later(@verification)
      else
        @verification.approve!
        VerificationMailer.approved(@verification).deliver_later
      end
    when :denied
      @verification.mark_as_rejected!(@verification.default_rejection_reason || "other")
    when :manual_review
      Slack::NotifyReviewQueueJob.perform_later(@verification)
    end
  end
end
