class Components::IdentityReview::AadhaarInfo < Components::Base
  def initialize(verification)
    @verification = verification
  end

  def view_template
    div class: "lowered padding" do
      h2(style: "margin-top: 0;") { "Aadhaar Information" }
      table style: "width: 100%;" do
        tr do
          td(style: "font-weight: bold; padding: 0.25rem 0;") { "Aadhaar Number:" }
          td(style: "padding: 0.25rem 0;") { @verification.identity.aadhaar_number }
        end
        tr do
          td(style: "font-weight: bold; padding: 0.25rem 0;") { "Uploaded:" }
          td(style: "padding: 0.25rem 0;") { @verification.pending_at&.strftime("%B %d, %Y at %I:%M %p") || "N/A" }
        end
      end
    end
  end
end
