# frozen_string_literal: true

class Components::IdentityReview::AadhaarInfo < Components::Base
  def initialize(verification)
    @verification = verification
  end

  def view_template
    div class: "lowered" do
      detail_row("aadhaar number", @verification.identity.aadhaar_number)
      detail_row("uploaded", @verification.pending_at&.strftime("%B %d, %Y at %I:%M %p") || "N/A")
    end
  end

  private

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
