class Components::VerificationStatusItem < Components::Base
  def initialize(identity:)
    @identity = identity
  end

  def status
    @identity.verification_status
  end

  def show?
    # Show if not verified and not ineligible
    status != "verified"
  end

  def completed?
    status == "verified"
  end

  def title
    case status
    when "needs_submission"
      I18n.t("home.completion_tasks.idv.verify_your_identity")
    when "pending"
      I18n.t("home.completion_tasks.idv.pending")
    when "ineligible"
      I18n.t("home.completion_tasks.idv.ineligible")
    else
      I18n.t("home.completion_tasks.idv.verify_your_identity")
    end
  end

  def description
    case status
    when "needs_submission"
      if @identity.needs_resubmission?
        I18n.t("home.completion_tasks.idv.desc_resubmit")
      else
        I18n.t("home.completion_tasks.idv.desc_submit")
      end
    when "pending"
      I18n.t("home.completion_tasks.idv.desc_pending")
    when "ineligible"
      reason = @identity.verification_status_reason
      if reason.present?
        "You're not eligible to verify: #{Verification::DocumentVerification::REJECTION_REASON_NAMES[reason] || reason}"
      else
        "You're not eligible for verification at this time"
      end
    else
      "Huh. That's weird."
    end
  end

  def url
    return nil if status == "pending" || status == "ineligible"
    new_verifications_path
  end

  def icon
    case status
    when "needs_submission"
      @identity.needs_resubmission? ? "reply" : "card-id"
    when "pending"
      "clock"
    when "ineligible"
      "forbidden"
    else
      "card-id"
    end
  end

  def clickable?
    url.present?
  end

  def view_template
    return unless show?

    if clickable?
      a(href: url, class: "profile-task") do
        render_content
      end
    else
      div(class: "profile-task profile-task-disabled") do
        render_content
      end
    end
  end

  private

  def render_content
    div(class: "task-icon") { helpers.inline_icon(icon, size: 24) }
    div(class: "task-content") do
      div(class: "task-title") { title }
      div(class: "task-description") { description }
    end
    if clickable?
      div(class: "task-action") { "→" }
    end
  end
end
