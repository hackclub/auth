# the rejection machinery, extracted.
#
# one hash to rule them all — declare your reasons,
# get everything else for free: enum, constants, names,
# options grouped for dropdowns, the "other" validation,
# the before/after callbacks for mark_as_rejected.
#
#   include Verification::Rejectable
#
#   rejection_reasons(
#     poor_quality: { name: "Poor image quality", fatal: false },
#     fraud:        { name: "Fraudulent submission", fatal: true }
#   )
#
module Verification::Rejectable
  extend ActiveSupport::Concern

  included do
    validates :rejection_reason, presence: true, if: :rejected?
    validate  :rejection_reason_details_present_when_reason_other
  end

  class_methods do
    def rejection_reasons(reasons)
      const_set(:REJECTION_REASONS, reasons.freeze)

      enum :rejection_reason, reasons.keys.index_with { |k| k.to_s }

      const_set(:RETRYABLE_REJECTION_REASONS, reasons.reject { |_, v| v[:fatal] }.keys.map(&:to_s).freeze)
      const_set(:FATAL_REJECTION_REASONS,     reasons.select  { |_, v| v[:fatal] }.keys.map(&:to_s).freeze)
      const_set(:REJECTION_REASON_NAMES,      reasons.transform_keys(&:to_s).transform_values { |v| v[:name] }.freeze)
    end
  end

  def rejection_reason_name = self.class::REJECTION_REASON_NAMES[rejection_reason] || rejection_reason

  def rejection_reason_options
    grouped = self.class::REJECTION_REASONS.group_by { |_, v| v[:fatal] ? :fatal : :retryable }
    grouped.transform_values { |pairs| pairs.map { |k, v| [v[:name], k.to_s] } }
  end

  private

  def fatal_rejection_reason?(reason)
    reason.present? && (super(reason) || self.class::FATAL_REJECTION_REASONS.include?(reason.to_s))
  end

  def rejection_reason_details_present_when_reason_other
    return unless rejection_reason == "other" && rejection_reason_details.blank?
    errors.add(:rejection_reason_details, "must be provided when rejection reason is 'other'")
  end

  # shared AASM callback bodies — call these from your state machine:
  #
  #   event :mark_as_rejected do
  #     transitions from: [:draft, :pending], to: :rejected
  #     before { |reason, details| set_rejection_fields(reason, details) }
  #     after  { notify_rejection }
  #   end

  def set_rejection_fields(reason, details = nil)
    self.rejection_reason = reason
    self.rejection_reason_details = details
    self.fatal = fatal_rejection_reason?(reason)
  end

  def notify_rejection
    if fatal_rejection?
      VerificationMailer.rejected_permanently(self).deliver_later
      Slack::NotifyGuardiansJob.perform_later(identity)
    else
      VerificationMailer.rejected_amicably(self).deliver_later
    end
  end
end
