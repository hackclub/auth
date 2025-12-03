# frozen_string_literal: true

class Components::IdentityReview::DocumentInfo < Components::Base
  def initialize(verification)
    @verification = verification
  end

  def view_template
    div class: "lowered" do
      detail_row("type", @verification.document_type)
      detail_row("uploaded", @verification.identity_document.created_at.strftime("%B %d, %Y at %I:%M %p"))
      if @verification.identity.country == "IN"
        detail_row("aadhaar password") do
          copy_to_clipboard(@verification.identity.suggested_aadhaar_password, tooltip_direction: "e")
        end
      end
      detail_row("status") do
        span class: "badge #{status_class}" do
          @verification.status.humanize
        end
      end
      detail_row("files", @verification.identity_document.files.count)
    end
  end

  private

  def status_class
    if @verification.pending?
      "pending"
    elsif @verification.approved?
      "success"
    else
      "danger"
    end
  end

  def detail_row(label, value = nil, &block)
    div class: "detail-row" do
      span(class: "detail-label") { label }
      span class: "detail-value" do
        if block_given?
          yield
        else
          plain value.to_s
        end
      end
    end
  end
end
