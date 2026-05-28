# frozen_string_literal: true

class Persona::VerificationPipelineJob < ApplicationJob
  queue_as :default

  def perform(verification)
    @verification = verification
    @identity = verification.identity
    @record = verification.persona_record

    run_resemblances
    run_decisioning
  end

  private

  def document_names
    return [] unless @record&.name_first.present? && @record&.name_last.present?

    [{ first: @record.name_first, last: @record.name_last, dob: @record.birthdate }]
  end

  def run_resemblances
    ResemblanceNoticerEngine.run(@identity, additional_names: document_names)
  end

  def run_decisioning
    verdict = Internal::Decisioning.run(@verification)

    case verdict
    when :approved
      @verification.approve!
    when :denied
      @verification.mark_as_rejected!(@verification.default_rejection_reason || "other")
    when :manual_review
      Slack::NotifyReviewQueueJob.perform_later(@verification)
    end
  end
end
